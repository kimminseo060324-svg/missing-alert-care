"""FCM 푸시(services/push.py)와 발송 시점 테스트. 실제 FCM은 부르지 않고 _send_message를 가짜로 바꾼다."""
import logging

import pytest

from services import push, sync
from test_sync import BASE, Clock, _fetch as fetch_rows, _row as row


@pytest.fixture(autouse=True)
def reset_push(monkeypatch):
    monkeypatch.setattr(push, "_app", None)
    monkeypatch.setattr(push, "_disabled", None)
    monkeypatch.setattr(push, "_last_fire", {})


@pytest.fixture
def fcm(monkeypatch):
    """가짜 FCM. sent에 (제목, 본문, data)를 모은다. fcm.fail=True면 예외를 낸다."""
    class Fake:
        fail = False
        sent = []

        def __call__(self, title, body, data):
            if self.fail:
                err = RuntimeError("응답 본문 SECRET-BODY")
                err.code = "UNAVAILABLE"
                raise err
            self.sent.append((title, body, data))
            return f"projects/x/messages/{len(self.sent)}"
    fake = Fake()
    fake.sent = []
    monkeypatch.setattr(push, "init", lambda: True)
    monkeypatch.setattr(push, "_send_message", fake)
    return fake


@pytest.fixture
def logs():
    got = []

    class Grab(logging.Handler):
        def emit(self, record):
            got.append(record.getMessage())
    h = Grab()
    push.log.addHandler(h)
    yield got
    push.log.removeHandler(h)


# 문구 ---------------------------------------------------------------------

@pytest.mark.parametrize("address, expected", [
    ("경기 오산시 양산동", "오산시"),
    ("경기도 수원시 영통구 매탄동", "수원시 영통구"),
    ("서울특별시 강남구 역삼동", "강남구"),
    ("세종특별자치시 조치원읍", "세종특별자치시"),
    ("오산시 궐동", "오산시"),
    ("", "지역 미확인"),
    (None, "지역 미확인"),
    ("양산동 어딘가", "지역 미확인"),
])
def test_region_of(address, expected):
    assert push.region_of(address) == expected


def test_issued_message_has_no_name_and_string_data():
    raw = {"msspsnIdntfccd": 9990001, "nm": "홍길동", "ageNow": 82, "age": 80, "sexdstnDscd": "남자",
           "occrAdres": "경기 오산시 양산동 123"}
    title, body, data = push.build("issued", raw, "수색중")
    assert (title, body) == ("실종경보", "오산시에서 82세 남성을 찾고 있어요")
    assert data == {"type": "missing_alert", "event": "issued", "alert_id": "9990001", "status": "수색중",
                    "region": "오산시", "version": "1"}  # 좌표가 없으면 lat/lng 키 없음
    assert "홍길동" not in title + body + str(data)


def test_issued_fallback_and_closed_text():
    _, body, _ = push.build("issued", {"msspsnIdntfccd": 1, "occrAdres": "경기 오산시 궐동"}, "수색중")
    assert body == "오산시에서 실종자를 찾고 있어요"
    title, body, data = push.build("closed", {"msspsnIdntfccd": 1}, "경보종료")
    assert (title, body) == ("실종경보 종료", "지역 미확인 실종경보가 종료됐어요")
    assert data["event"] == "closed" and data["status"] == "경보종료"


def test_lat_lng_added_only_when_known(monkeypatch):
    monkeypatch.setattr(push, "coordinates", lambda raw: (37.15, 127.07))
    _, _, data = push.build("issued", {"msspsnIdntfccd": 1}, "수색중")
    assert (data["lat"], data["lng"]) == ("37.15", "127.07")


# 키가 없을 때 -----------------------------------------------------------------

def test_no_key_path_disables_push_but_fire_works(client, logs):
    res = client.post("/test/fire/9990001")
    assert res.status_code == 200
    assert res.json()["push"]["status"] == "skipped"
    assert "FIREBASE_SERVICE_ACCOUNT_PATH" in res.json()["push"]["reason"]
    client.post("/test/fire/9990002")
    assert len(logs) == 1  # 끈 이유는 한 번만


def test_missing_or_bad_key_file_disables_without_leaking(monkeypatch, tmp_path, logs):
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT_PATH", str(tmp_path / "none.json"))
    assert push.init() is False
    assert "키 파일이 없어" in push._disabled

    bad = tmp_path / "bad.json"
    bad.write_text('{"type": "service_account", "private_key": "SECRET-KEY"}')
    monkeypatch.setattr(push, "_disabled", None)
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT_PATH", str(bad))
    assert push.init() is False
    assert "SECRET" not in " ".join(logs) and "SECRET" not in push._disabled
    assert str(tmp_path) not in " ".join(logs)


# 시연용 API ------------------------------------------------------------------

def test_fire_sends_once_per_minute(client, fcm):
    first = client.post("/test/fire/9990001").json()["push"]
    assert first == {"status": "sent", "reason": None, "message_id": "projects/x/messages/1"}
    title, body, data = fcm.sent[0]
    assert data["alert_id"] == "9990001" and data["status"] == "수색중" and data["event"] == "issued"
    again = client.post("/test/fire/9990001").json()["push"]
    assert again["status"] == "skipped" and "60초" in again["reason"]
    assert client.post("/test/fire/9990002").json()["push"]["status"] == "sent"  # 다른 경보는 보냄
    assert len(fcm.sent) == 2


def test_fire_dedup_expires(client, fcm, monkeypatch):
    client.post("/test/fire/9990001")
    key = (9990001, "issued")
    monkeypatch.setitem(push._last_fire, key, push._last_fire[key] - push.FIRE_DEDUP_SEC)
    assert client.post("/test/fire/9990001").json()["push"]["status"] == "sent"


def test_found_sends_closed(client, fcm):
    res = client.post("/test/found/9990003").json()["push"]
    assert res["status"] == "sent"
    title, body, data = fcm.sent[0]
    assert title == "실종경보 종료" and data["event"] == "closed" and data["status"] == "발견완료"


def test_end_sends_closed_once_per_minute(client, fcm):
    client.post("/test/fire/9990001")  # issued를 보낸 직후여도 closed는 따로 센다
    res = client.post("/test/end/9990001").json()["push"]
    assert res["status"] == "sent"
    title, _, data = fcm.sent[-1]
    assert title == "실종경보 종료" and data["event"] == "closed" and data["status"] == "경보종료"
    again = client.post("/test/end/9990001").json()["push"]
    assert again["status"] == "skipped" and "60초" in again["reason"]
    assert len(fcm.sent) == 2

def test_send_failure_reports_code_only(client, fcm, logs):
    fcm.fail = True
    res = client.post("/test/fire/9990001").json()["push"]
    assert res == {"status": "failed", "reason": "RuntimeError(UNAVAILABLE)", "message_id": None}
    assert "SECRET" not in " ".join(logs)
    fcm.fail = False
    assert client.post("/test/fire/9990001").json()["push"]["status"] == "sent"  # 실패는 60초 제한에 안 걸림


# 실제 데이터 조회(sync) -------------------------------------------------------------

@pytest.fixture
def run(tmp_path):
    tracker = sync.Tracker(tmp_path / "state.json")
    clock = Clock()

    def poll(rows):
        return sync.poll_once(tracker, "id", "key", 0, clock.tick(), fetch_rows(rows))
    poll.tracker = tracker
    return poll


def test_sync_success_sets_notified(run, fcm):
    run(BASE)
    run(BASE + [row(4)])
    a = run.tracker.alerts[4]
    assert a["notified"] is True and a["push"] is None
    assert [d["alert_id"] for _, _, d in fcm.sent] == ["4"]
    run(BASE + [row(4)])
    assert len(fcm.sent) == 1  # 다시 보내지 않음


def test_sync_failure_retries_next_poll(run, fcm):
    run(BASE)
    fcm.fail = True
    run(BASE + [row(4)])
    a = run.tracker.alerts[4]
    assert a["notified"] is False and a["push"] == "issued"  # 다음 회차 재전송 대상
    fcm.fail = False
    run(BASE + [row(4)])
    assert a["notified"] is True and a["push"] is None
    assert len(fcm.sent) == 1


def test_sync_ended_sends_closed(run, fcm):
    run(BASE)
    for _ in range(3):
        run([row(1), row(3)])
    assert [(t, d["alert_id"], d["status"]) for t, _, d in fcm.sent] == [("실종경보 종료", "2", "경보종료")]
    assert run.tracker.alerts[2]["push"] is None


def test_sync_without_key_clears_pending(run):
    run(BASE)
    run(BASE + [row(4)])
    a = run.tracker.alerts[4]
    assert a["push"] is None and a["notified"] is False  # 푸시가 꺼져 있으면 쌓아 두지 않음
