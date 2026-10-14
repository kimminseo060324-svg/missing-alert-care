"""안전Dream 주기 조회·신규·종료 판단(services/sync.py) 테스트.

실제 API는 부르지 않는다. fetch를 가짜로 넘기거나 poll_once를 바꿔 네트워크 없이 돈다.
상태 파일은 tmp_path에 쓰고, 실명·주소·사진이 없는 가짜 데이터만 쓴다.
"""
import logging
import os
import sys
import threading
import time
import types
from datetime import datetime, timedelta

import pytest

from routers import alerts
from services import safe182, sync

NOW = datetime(2026, 10, 14, 9, 0, tzinfo=sync.KST)
STEP = timedelta(minutes=5)
RECENT, OLD = "20261013", "20200101"


def _row(sid, occrde=RECENT):
    return {"msspsnIdntfccd": sid, "occrde": occrde, "nm": "테스트", "writngTrgetDscd": "070",
            "tknphotoFile": "fake-photo", "tknphotolength": 10}


def _fetch(rows, total=None, received=None):
    """safe182.fetch_all 대신 쓸 가짜. 호출 수도 센다."""
    def fetch(api_id, api_key, count_call):
        count_call()
        return rows, len(rows) if received is None else received, len(rows) if total is None else total, 0
    return fetch


@pytest.fixture
def logs():
    """sync 로거 메시지를 모은다 (로거가 propagate=False라 caplog 대신 직접 붙인다)."""
    got = []

    class Grab(logging.Handler):
        def emit(self, record):
            got.append(record.getMessage())
    h = Grab()
    sync.log.addHandler(h)
    yield got
    sync.log.removeHandler(h)


@pytest.fixture
def pushed(monkeypatch):
    calls = []
    def fake(new):
        calls.append([r["msspsnIdntfccd"] for r in new])
        return {r["msspsnIdntfccd"]: {"status": "sent"} for r in new}
    monkeypatch.setattr(sync, "on_new_alert", fake)
    return calls


@pytest.fixture
def tracker(tmp_path):
    return sync.Tracker(tmp_path / "state.json")


class Clock:
    def __init__(self):
        self.now = NOW

    def tick(self, delta=STEP):
        self.now += delta
        return self.now


@pytest.fixture
def run(tracker):
    """poll_once를 한 회차씩 돌린다."""
    clock = Clock()

    def poll(rows, **kw):
        return sync.poll_once(tracker, "id", "key", 0, clock.tick(), _fetch(rows, **kw))
    poll.clock = clock
    return poll


BASE = [_row(1), _row(2), _row(3)]


# 신규 판단 ------------------------------------------------------------------

def test_first_run_is_baseline_only(run, tracker, pushed):
    run(BASE)
    assert tracker.baseline_done
    assert set(tracker.alerts) == {1, 2, 3}
    assert not any(a["notified"] for a in tracker.alerts.values())
    assert pushed == []


def test_new_id_with_recent_date_is_new(run, pushed):
    run(BASE)
    run(BASE + [_row(4, RECENT)])
    assert pushed == [[4]]


def test_new_id_with_old_date_is_not_new(run, tracker, pushed):
    run(BASE)
    run(BASE + [_row(5, OLD), _row(6, "깨진날짜")])
    assert pushed == []
    assert tracker.status_of(5) == sync.SEARCHING


def test_same_id_is_never_new_again(run, pushed):
    run(BASE)
    run(BASE + [_row(4)])
    run(BASE)              # 4번 빠짐
    run(BASE + [_row(4)])  # 다시 나타남
    assert pushed == [[4]]


# 종료 판단 ------------------------------------------------------------------

def test_three_misses_end_alert_and_hide_name_photo(run, tracker):
    run(BASE)
    for _ in range(2):
        run([_row(1), _row(3)])
        assert tracker.status_of(2) == sync.SEARCHING  # 종료 후보
    run([_row(1), _row(3)])
    assert tracker.status_of(2) == sync.ENDED
    items, _ = tracker.snapshot(run.clock.now)
    ended = next(r for r in items if r["msspsnIdntfccd"] == 2)
    assert ended["nm"] is None and ended["tknphotoFile"] is None and ended["tknphotolength"] == 0
    assert next(r for r in items if r["msspsnIdntfccd"] == 1)["nm"] == "테스트"  # 다른 경보는 그대로


def test_ended_alert_restored_when_it_reappears(run, tracker):
    run(BASE)
    for _ in range(3):
        run([_row(1), _row(3)])
    run(BASE)
    a = tracker.alerts[2]
    assert (a["status"], a["ended_at"], a["miss_count"]) == (sync.SEARCHING, None, 0)


def test_ended_alert_hidden_from_list_and_detail_after_three_days(run, tracker, monkeypatch, client):
    run(BASE)
    for _ in range(3):
        run([_row(1), _row(3)])
    ended_at = tracker.alerts[2]["ended_at"]
    monkeypatch.setattr(sync, "TRACKER", tracker)
    monkeypatch.setattr(alerts, "source", safe182)  # 이 테스트만 실제 모드 모듈로 응답

    monkeypatch.setattr(sync, "_now", lambda: ended_at + timedelta(days=2))
    listed = {x["msspsnIdntfccd"]: x for x in client.get("/alerts").json()["list"]}
    assert listed[2]["status"] == "경보종료" and listed[2]["nm"] is None
    assert client.get("/alerts/2").status_code == 200

    monkeypatch.setattr(sync, "_now", lambda: ended_at + timedelta(days=3, minutes=1))
    assert 2 not in [x["msspsnIdntfccd"] for x in client.get("/alerts").json()["list"]]
    assert client.get("/alerts/2").status_code == 404
    assert client.post("/test/fire/1").status_code == 403  # 실제 모드에서 시연용 API 막힘
    assert client.post("/test/end/1").status_code == 403
    assert client.post("/test/found/1").status_code == 403
    assert tracker.status_of(1) == sync.SEARCHING  # 막힌 요청은 상태를 바꾸지 않는다


# 조회 회차 처리 --------------------------------------------------------------

def test_count_mismatch_round_is_not_compared(run, tracker, logs):
    run(BASE, total=5)
    assert not tracker.baseline_done and tracker.alerts == {}
    run(BASE)
    run([_row(1)], received=1, total=3)  # 이 회차는 비교하지 않으므로 2, 3번 누락으로 세지 않는다
    assert tracker.alerts[2]["miss_count"] == 0
    assert any("비교에 쓰지 않습니다" in m for m in logs)


def test_result_code_80_stops_for_the_day(tracker, logs):
    calls = []

    def limited(api_id, api_key, count_call):
        calls.append(1)
        count_call()
        raise safe182.DailyLimitExceeded("안전Dream API 일일 호출 한도를 넘었습니다 (결과 코드 80)")

    wait, _ = sync.poll_once(tracker, "id", "key", 0, NOW, limited)
    midnight = datetime(2026, 10, 15, tzinfo=sync.KST)
    assert wait == int((midnight - NOW).total_seconds())
    assert tracker.stopped_today(NOW) and "한도" in tracker.snapshot(NOW)[1]

    sync.poll_once(tracker, "id", "key", 0, NOW + STEP, limited)
    assert len(calls) == 1  # 같은 날에는 다시 부르지 않는다

    wait, _ = sync.poll_once(tracker, "id", "key", 0, midnight + timedelta(minutes=1), _fetch(BASE))
    assert wait == sync.INTERVAL and tracker.baseline_done  # 다음 날 다시 조회


def test_failures_back_off(tracker):
    def broken(api_id, api_key, count_call):
        raise safe182.Safe182Error("안전Dream API가 HTTP 500 오류를 돌려줬습니다")
    waits, failures = [], 0
    for _ in range(4):
        wait, failures = sync.poll_once(tracker, "id", "key", failures, NOW, broken)
        waits.append(wait)
    assert waits == [60, 300, 900, 900]
    assert sync.poll_once(tracker, "id", "key", failures, NOW, _fetch(BASE)) == (sync.INTERVAL, 0)


def test_state_file_has_no_names_or_photos(run, tracker):
    run(BASE)
    text = tracker.state_path.read_text(encoding="utf-8")
    assert "테스트" not in text and "fake-photo" not in text
    reloaded = sync.Tracker(tracker.state_path)
    assert set(reloaded.alerts) == {1, 2, 3} and not reloaded.baseline_done  # 다시 켜면 첫 회차는 기준만


# 시작·잠금·간격 ---------------------------------------------------------------

def _fake_fcntl():
    """fcntl 흉내 (윈도우에는 fcntl이 없다). 같은 파일을 다른 파일 객체로 다시 잠그면 BlockingIOError.
    앞서 잠근 파일 객체가 닫혔으면 잠금이 풀린 것으로 본다 (실제 flock과 같은 동작)."""
    holders = {}

    def flock(f, flags):
        key = os.path.realpath(f.name)
        holder = holders.get(key)
        if holder is not None and holder is not f and not holder.closed:
            raise BlockingIOError(f"이미 잠긴 파일: {os.path.basename(key)}")
        holders[key] = f

    return types.SimpleNamespace(LOCK_EX=2, LOCK_NB=4, flock=flock)


@pytest.fixture
def fresh_sync(monkeypatch, tmp_path):
    """start()가 쓰는 전역 TRACKER와 환경변수를 테스트용으로 바꾼다. poll_once는 네트워크 없이 기록만.
    fcntl은 모든 OS에서 가짜로 바꿔, 윈도우에서도 같은 테스트가 돈다."""
    monkeypatch.setitem(sys.modules, "fcntl", _fake_fcntl())
    monkeypatch.setattr(sync, "TRACKER", sync.Tracker())
    monkeypatch.setattr(sync, "INTERVAL", sync.INTERVAL)  # start()가 바꾼 전역 간격을 테스트 뒤 되돌린다
    monkeypatch.setenv("SYNC_STATE_DIR", str(tmp_path))
    monkeypatch.setenv("MISSING_ALERT_API_ID", "fake-id")
    monkeypatch.setenv("MISSING_ALERT_API_KEY", "fake-key")
    polled = []

    def fake_poll(tracker, api_id, api_key, failures, now=None, fetch=None):
        polled.append(1)
        return sync.INTERVAL, 0
    monkeypatch.setattr(sync, "poll_once", fake_poll)
    stops = []
    yield polled, stops
    for s in stops:
        s()


def test_missing_key_fails_with_notice_and_prints_nothing_secret(monkeypatch, fresh_sync, logs):
    monkeypatch.delenv("MISSING_ALERT_API_KEY")
    assert sync.start() is None
    items, notice = sync.TRACKER.snapshot()
    assert items == [] and "MISSING_ALERT_API_KEY" in notice
    joined = " ".join(logs) + notice
    assert "fake-id" not in joined and "safe182.go.kr" not in joined


def test_second_worker_does_not_poll(fresh_sync, logs):
    polled, stops = fresh_sync
    first = sync.start()
    assert first is not None
    stops.append(first)
    assert sync.start() is None  # 같은 상태 폴더의 잠금을 이미 잡고 있음
    assert sync.TRACKER.follower
    assert any("이미 조회 중" in m for m in logs)


@pytest.mark.parametrize(("value", "expected"), [
    ("0", 300), ("-5", 300), ("abc", 300), ("30", 60), ("", 300), (None, 300), ("300", 300),
    ("99999999", 86400), ("86400", 86400), ("86401", 86400), ("60", 60),
])
def test_read_interval(value, expected):
    assert sync.read_interval(value)[0] == expected


def _start_and_wait_first_poll(polled, stops):
    """start()로 새로 생긴 동기화 스레드를 돌려준다 (앞 테스트에서 남은 스레드와 섞이지 않게)."""
    before = set(threading.enumerate())
    stops.append(sync.start())
    deadline = time.time() + 5
    while not polled and time.time() < deadline:
        time.sleep(0.01)
    time.sleep(0.1)  # 첫 조회 뒤 대기(stop.wait)에 들어갈 시간
    return next(t for t in set(threading.enumerate()) - before if t.name == "safe182-sync")


def test_huge_interval_does_not_kill_sync_thread(monkeypatch, fresh_sync, logs):
    polled, stops = fresh_sync
    monkeypatch.setenv("SAFE182_SYNC_INTERVAL_SEC", "99999999")
    thread = _start_and_wait_first_poll(polled, stops)
    assert polled and thread.is_alive()
    assert sync.INTERVAL == 86400
    assert any("86400초로 내림" in m for m in logs)


def test_wait_error_keeps_thread_alive_without_busy_loop(monkeypatch, fresh_sync, logs):
    """stop.wait()가 OverflowError를 내도 스레드는 살아 있고, 기본 간격으로 대신 기다린다."""
    polled, stops = fresh_sync
    waits = []

    class BrokenFirstWait(threading.Event):
        def wait(self, timeout=None):
            waits.append(timeout)
            if len(waits) == 1:
                raise OverflowError("timestamp out of range for platform time_t")
            return super().wait(timeout)

    # sync 모듈 안의 threading만 바꾼다 (다른 코드의 threading.Event는 그대로)
    monkeypatch.setattr(sync, "threading", types.SimpleNamespace(
        Event=BrokenFirstWait, Thread=threading.Thread, Lock=threading.Lock))
    thread = _start_and_wait_first_poll(polled, stops)
    time.sleep(0.2)
    assert thread.is_alive()
    assert len(polled) == 1  # 대기 실패 뒤에도 바로 다시 조회하지 않는다
    assert waits[:2] == [sync.INTERVAL, sync.DEFAULT_INTERVAL]
    assert any("대신 기다립니다" in m for m in logs)


def test_estimate_daily_calls():
    assert sync.estimate_daily_calls(112, 300) == (2, 576, 192)
    assert sync.estimate_daily_calls(112, 60)[1] == 2880
    assert sync.estimate_daily_calls(0, 300)[0] == 1
