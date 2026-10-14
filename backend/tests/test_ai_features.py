"""AI 옷차림 특징 연결(services/ai_features.py) 테스트. 실제 Gemini는 부르지 않고 _call_gemini를 가짜로 바꾼다.

`with TestClient(app)`로 서버 시작(lifespan)을 돌려야 백그라운드 추출 태스크가 뜬다.
"""
import logging
import threading
import time
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from main import app
from services import ai_features, push, sync
from test_sync import _fetch, _row

SIDS = [9990001, 9990002, 9990003, 9990004, 9990005, 9990006]
FAKE_OUT = {"upper": {"type": "점퍼", "color": "회색"}, "lower": {"type": "바지", "color": "검정"},
            "shoes": {"type": "", "color": ""}, "accessories": [{"type": "모자", "color": "빨강"}],
            "negatives": [], "summary": ["회색 점퍼", "검정 바지", "빨간 모자", "네 번째는 잘림"]}


@pytest.fixture(autouse=True)
def fresh(monkeypatch, tmp_path):
    monkeypatch.setattr(ai_features, "_results", {})
    monkeypatch.setattr(ai_features, "_cache", {})
    monkeypatch.setattr(ai_features, "_waiting", {})
    monkeypatch.setattr(ai_features, "_current", {})
    monkeypatch.setattr(ai_features, "_client", None)
    monkeypatch.setattr(ai_features, "CACHE_PATH", tmp_path / "ai_cache.json")
    monkeypatch.setattr(ai_features.extract_ai, "call_interval", lambda: 0)
    monkeypatch.setenv("GEMINI_API_KEY", "fake-key")
    monkeypatch.delenv("AI_EXTRACT_ENABLED", raising=False)


@pytest.fixture
def gemini(monkeypatch):
    """가짜 Gemini. calls에 받은 원문을 모은다. fail=True면 예외, gate가 있으면 열릴 때까지 기다린다."""
    class Fake:
        calls, fail, gate = [], False, None

        def __call__(self, text):
            self.calls.append(text)
            if self.gate:
                self.gate.wait(5)
            if self.fail:
                raise RuntimeError(f"응답 본문 SECRET-BODY {text}")
            return FAKE_OUT
    fake = Fake()
    fake.calls = []
    monkeypatch.setattr(ai_features, "_call_gemini", fake)
    return fake


@pytest.fixture
def logs():
    got = []

    class Grab(logging.Handler):
        def emit(self, record):
            got.append(record.getMessage())
    h = Grab()
    ai_features.log.addHandler(h)
    yield got
    ai_features.log.removeHandler(h)


def wait_until(check, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return True
        time.sleep(0.01)
    return False


def all_settled():
    return all(ai_features.view(s)["status"] != "pending" for s in SIDS)


def check_shape(ai, full):
    if full:
        assert set(ai) == {"status", "clothing", "summary", "extracted_at"}
        assert set(ai["clothing"]) == {"upper", "lower", "shoes", "accessories"}
        assert all(isinstance(v, list) and all(isinstance(x, str) and x for x in v) for v in ai["clothing"].values())
        if ai["status"] != "done":
            assert ai["clothing"] == {"upper": [], "lower": [], "shoes": [], "accessories": []}
            assert ai["extracted_at"] is None
        else:
            assert isinstance(ai["extracted_at"], str)
    else:
        assert set(ai) == {"status", "summary"}
    assert ai["status"] in ("done", "pending", "unavailable")
    assert isinstance(ai["summary"], list) and len(ai["summary"]) <= 3
    if ai["status"] != "done":
        assert ai["summary"] == []


def check_all(c, status):
    """목록·상세 모든 경보에 ai가 있고 모양이 맞는지."""
    items = c.get("/alerts").json()["list"]
    assert len(items) == len(SIDS)
    for it in items:
        check_shape(it["ai"], full=False)
        assert it["ai"]["status"] == status
    for sid in SIDS:
        res = c.get(f"/alerts/{sid}")
        assert res.status_code == 200
        check_shape(res.json()["ai"], full=True)
        assert res.json()["ai"]["status"] == status


def test_success_is_done(gemini):
    with TestClient(app) as c:
        assert wait_until(all_settled)
        check_all(c, "done")
        ai = c.get("/alerts/9990001").json()["ai"]
        assert ai["clothing"] == {"upper": ["회색 점퍼"], "lower": ["검정 바지"], "shoes": [], "accessories": ["빨강 모자"]}
        assert ai["summary"] == ["회색 점퍼", "검정 바지", "빨간 모자"]  # 최대 3개
        assert c.get("/alerts").json()["list"][0]["ai"]["summary"] == ["회색 점퍼", "검정 바지", "빨간 모자"]
    assert len(gemini.calls) == len(SIDS)
    assert ai_features.CACHE_PATH.exists()  # sample 모드는 파일 캐시 저장


def test_original_fields_unchanged(client):
    """ai만 더해지고 기존 필드는 그대로."""
    body = client.get("/alerts/9990001").json()
    assert {"status", "issued_at", "found_at", "ended_at", "target_label", "photo_url", "source", "is_sample",
            "nm", "occrAdres", "alldressingDscd"} <= set(body)
    check_shape(body["ai"], full=True)


def test_no_key_is_unavailable_and_alerts_push_work(gemini, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "")
    with TestClient(app) as c:
        check_all(c, "unavailable")
        fire = c.post("/test/fire/9990001").json()
        assert fire["status"] == "수색중" and "push" in fire
        check_shape(fire["ai"], full=True)
    assert gemini.calls == []


def test_disabled_is_unavailable(gemini, monkeypatch):
    monkeypatch.setenv("AI_EXTRACT_ENABLED", "0")
    with TestClient(app) as c:
        check_all(c, "unavailable")
    assert gemini.calls == []


def test_failure_is_unavailable_and_nothing_leaks(gemini, logs, monkeypatch):
    sent = []
    monkeypatch.setattr(push, "init", lambda: True)
    monkeypatch.setattr(push, "_send_message", lambda *a: sent.append(a) or "msg-id")
    gemini.fail = True
    with TestClient(app) as c:
        assert wait_until(all_settled)
        check_all(c, "unavailable")
        fire = c.post("/test/fire/9990001").json()
        assert fire["push"]["status"] == "sent" and fire["status"] == "수색중"
        assert c.post("/test/found/9990002").json()["push"]["status"] == "sent"
        assert wait_until(all_settled)
    text = " ".join(logs)
    assert "SECRET-BODY" not in text and "fake-key" not in text and "찾습니다" not in text
    assert "AI 추출 실패 (RuntimeError)" in text


def test_retry_after_failure_on_fire(gemini):
    gemini.fail = True
    with TestClient(app) as c:
        assert wait_until(all_settled)
        gemini.fail = False
        c.post("/test/fire/9990001")
        assert wait_until(lambda: ai_features.view(9990001)["status"] == "done")


def test_same_text_calls_once(gemini, monkeypatch):
    monkeypatch.setattr(ai_features, "source_text", lambda raw: "회색 점퍼 입은 70대 남성을 찾습니다")
    with TestClient(app) as c:
        assert wait_until(all_settled)
        check_all(c, "done")
        c.post("/test/fire/9990003")  # 캐시에 있어 다시 부르지 않음
        assert c.get("/alerts/9990003").json()["ai"]["status"] == "done"
    assert len(gemini.calls) == 1


def test_cache_key_ignores_personal_info(gemini, monkeypatch):
    """개인정보를 지운 뒤 같은 문장이면 같은 키 → 한 번만 부른다."""
    texts = {9990001: "홍길동씨(남,70)를 찾습니다. 회색 점퍼", 9990002: "김철수씨(남,70)를 찾습니다. 회색 점퍼"}
    monkeypatch.setattr(ai_features, "source_text", lambda raw: texts.get(raw["msspsnIdntfccd"]))
    with TestClient(app):
        assert wait_until(all_settled)
    assert len(gemini.calls) == 1
    assert ai_features.view(9990001)["status"] == ai_features.view(9990002)["status"] == "done"
    assert ai_features.view(9990003)["status"] == "unavailable"  # 보낼 글 없음


def test_pending_can_be_read(gemini):
    gemini.gate = threading.Event()
    with TestClient(app) as c:
        assert wait_until(lambda: gemini.calls)
        check_all(c, "pending")
        gemini.gate.set()
        assert wait_until(all_settled)
        check_all(c, "done")


def test_sequential_with_interval(gemini, monkeypatch):
    monkeypatch.setattr(ai_features.extract_ai, "call_interval", lambda: 0.05)
    stamps = []
    orig = ai_features._call_gemini
    monkeypatch.setattr(ai_features, "_call_gemini", lambda t: stamps.append(time.monotonic()) or orig(t))
    with TestClient(app):
        assert wait_until(all_settled)
    gaps = [b - a for a, b in zip(stamps, stamps[1:])]
    assert len(stamps) == len(SIDS) and all(g >= 0.05 for g in gaps)


def test_safe182_mode_never_writes_file_and_is_off_by_default(gemini, monkeypatch):
    monkeypatch.setattr(ai_features, "MODE", "safe182")
    assert ai_features.enabled() is False
    assert ai_features.source_text({"msspsnIdntfccd": 9990001}) is None  # 재난문자 연동 없음
    monkeypatch.setenv("AI_EXTRACT_ENABLED", "1")
    monkeypatch.setattr(ai_features, "source_text", lambda raw: "회색 점퍼 남성을 찾습니다")
    with TestClient(app):
        ai_features.submit([{"msspsnIdntfccd": 1}])
        assert wait_until(lambda: ai_features.view(1)["status"] == "done")
    assert not ai_features.CACHE_PATH.exists()


def test_sync_submits_new_alerts_without_waiting(monkeypatch, tmp_path):
    got = []
    monkeypatch.setattr(ai_features, "submit", lambda rows: got.append([r["msspsnIdntfccd"] for r in rows]))
    tracker = sync.Tracker(tmp_path / "state.json")
    now = datetime(2026, 10, 14, 9, 0, tzinfo=sync.KST)
    first = [_row(1)]
    sync.poll_once(tracker, "id", "key", 0, now, _fetch(first))
    sync.poll_once(tracker, "id", "key", 0, now + timedelta(minutes=5), _fetch(first + [_row(2)]))
    assert got == [[], [2]]  # 처음 목록은 기준, 다음 회차 신규만


def test_without_server_start_ai_is_unavailable(client):
    """서버 시작(lifespan) 없이도 ai 필드는 항상 같은 모양."""
    for it in client.get("/alerts").json()["list"]:
        check_shape(it["ai"], full=False)
    check_shape(client.post("/test/fire/9990001").json()["ai"], full=True)


def test_key_error_from_sdk_does_not_escape(monkeypatch):
    """get_client가 SystemExit를 내도 워커는 살아 있고 unavailable."""
    def no_key(text):
        raise SystemExit("[오류] GEMINI_API_KEY가 없습니다")
    monkeypatch.setattr(ai_features, "_call_gemini", no_key)
    with TestClient(app) as c:
        assert wait_until(all_settled)
        check_all(c, "unavailable")
        assert not ai_features._task.done()  # 워커가 죽지 않음


def test_submit_after_loop_closed_is_unavailable(gemini):
    with TestClient(app):
        assert wait_until(all_settled)
        loop = ai_features._loop
    ai_features._loop = loop  # 닫힌 루프에 넣으려는 상황 (서버 종료 중 sync 스레드)
    try:
        ai_features._cache.clear()
        ai_features.submit([{"msspsnIdntfccd": 9990001}])
        assert ai_features.view(9990001)["status"] == "unavailable"
    finally:
        ai_features._loop = None


def test_clothing_label_without_color():
    out = {**FAKE_OUT, "shoes": {"type": "운동화", "color": ""}, "accessories": [{"type": "지팡이", "color": ""}]}
    c = ai_features._to_result(out)["clothing"]
    assert c["shoes"] == ["운동화"] and c["accessories"] == ["지팡이"]


def test_shutdown_does_not_wait_for_running_call(gemini):
    """Gemini 호출(재시도 대기 포함)이 길어져도 서버 종료는 기다리지 않는다."""
    gemini.gate = threading.Event()  # 열지 않음 → 가짜 호출이 5초 동안 멈춰 있음
    with TestClient(app):
        assert wait_until(lambda: gemini.calls)
        t = time.monotonic()
    assert time.monotonic() - t < 2
    gemini.gate.set()



# 캐시 키에 설정(모델·프롬프트·스키마) 포함 -----------------------------------------------

def run_server():
    """서버를 한 번 켰다 끈다 (가상 경보 6건 추출이 끝날 때까지). 끈 뒤 메모리 캐시를 비워 재시작을 흉내 낸다."""
    with TestClient(app):
        assert wait_until(all_settled)
    ai_features._cache.clear()
    ai_features._results.clear()


def test_same_config_same_text_reuses_file_cache(gemini):
    run_server()
    run_server()  # 재시작: 파일 캐시에서 읽어 다시 부르지 않음
    assert len(gemini.calls) == len(SIDS)


@pytest.mark.parametrize("change", ["model", "prompt", "schema", "colors"])
def test_config_change_extracts_again(gemini, monkeypatch, change):
    run_server()
    before = ai_features.config_hash()
    if change == "model":
        monkeypatch.setenv("GEMINI_MODEL", "other-model")
    elif change == "prompt":
        monkeypatch.setattr(ai_features.extract_ai, "PROMPT", ai_features.extract_ai.PROMPT + "\n10. 추가 규칙")
    elif change == "colors":  # 프롬프트에 채워 넣는 표준 색 목록만 바뀜 (PROMPT 템플릿은 그대로)
        monkeypatch.setattr(ai_features.extract_ai, "STANDARD_COLORS", ai_features.extract_ai.STANDARD_COLORS + ["새색"])
    else:
        schema = {**ai_features.extract_ai.AI_RESPONSE_SCHEMA, "description": "바뀐 스키마"}
        monkeypatch.setattr(ai_features.extract_ai, "AI_RESPONSE_SCHEMA", schema)
    assert ai_features.config_hash() != before
    run_server()
    assert len(gemini.calls) == 2 * len(SIDS)  # 설정이 바뀌어 모두 새로 추출


def test_cache_file_has_hashes_only(gemini):
    import json
    run_server()
    text = ai_features.CACHE_PATH.read_text(encoding="utf-8")
    data = json.loads(text)
    assert len(data) == len(SIDS)
    assert all(set(r) == {"config", "clothing", "summary", "extracted_at"} for r in data.values())
    assert all(r["config"] == ai_features.config_hash() for r in data.values())
    assert ai_features.extract_ai.model_name() not in text  # 모델명 원문 없음
    assert "재난문자를 읽고" not in text and "찾습니다" not in text  # 프롬프트·문자 원문 없음


@pytest.mark.parametrize("content", [
    "OLD",  # 예전 형식: 설정 해시 없음, 옷 칸이 {type, color}
    '[1, 2, 3]',  # 객체가 아님
    '{"x": "not-an-object"}',
    'not json',
])
def test_old_or_broken_cache_file_is_ignored(gemini, logs, content):
    import json
    if content == "OLD":
        text = "회색 점퍼 남성을 찾습니다"
        old = {"clothing": {"upper": [{"type": "점퍼", "color": "회색"}], "lower": [], "shoes": [], "accessories": []},
               "summary": ["회색 점퍼"], "extracted_at": "2026-10-15T00:00:00+09:00"}
        texts = [ai_features.source_text({"msspsnIdntfccd": s}) for s in SIDS]
        keys = [ai_features._sha(ai_features.redact(t)) for t in texts]  # 예전 키 방식 (문장만)
        keys += [ai_features._key(t, ai_features.config_hash()) for t in texts + [text]]  # 지금 키지만 설정 해시 없음
        content = json.dumps({k: old for k in keys})
    ai_features.CACHE_PATH.write_text(content, encoding="utf-8")
    run_server()  # 오류 없이 켜지고
    assert len(gemini.calls) == len(SIDS)  # 전부 새로 추출
    data = json.loads(ai_features.CACHE_PATH.read_text(encoding="utf-8"))  # 새 형식으로 다시 저장됨
    assert all(r.get("config") == ai_features.config_hash() for r in data.values())
    assert not any("Traceback" in m for m in logs)



@pytest.mark.parametrize("entry", [
    {"clothing": {"upper": "회색 점퍼", "lower": [], "shoes": [], "accessories": []}, "summary": [], "extracted_at": "t"},
    {"clothing": {"upper": [], "lower": [], "shoes": [], "accessories": []}, "summary": "회색 점퍼", "extracted_at": "t"},
    {"clothing": {"upper": [], "lower": [], "shoes": [], "accessories": []}, "summary": ["a", "b", "c", "d"],
     "extracted_at": "t"},
    {"clothing": {"upper": [], "lower": [], "shoes": []}, "summary": [], "extracted_at": "t"},
    {"clothing": {"upper": [1], "lower": [], "shoes": [], "accessories": []}, "summary": [], "extracted_at": "t"},
    {"clothing": [], "summary": [], "extracted_at": "t"},
    {"clothing": {"upper": [], "lower": [], "shoes": [], "accessories": []}, "summary": [], "extracted_at": None},
])
def test_wrong_shape_entry_with_current_config_is_ignored(gemini, entry):
    """설정 해시가 맞아도 모양이 틀린 항목(문자열 칸, 요약 4개 등)은 버리고 새로 추출한다."""
    import json
    keys = [ai_features._key(ai_features.source_text({"msspsnIdntfccd": s}), ai_features.config_hash()) for s in SIDS]
    ai_features.CACHE_PATH.write_text(json.dumps({k: {"config": ai_features.config_hash(), **entry} for k in keys}),
                                      encoding="utf-8")
    with TestClient(app) as c:
        assert wait_until(all_settled)
        for it in c.get("/alerts").json()["list"]:
            check_shape(it["ai"], full=False)
    assert len(gemini.calls) == len(SIDS)



# 늦게 끝난 예전 요청이 최신 결과를 덮어쓰지 않기 -------------------------------------------

TEXT_A, TEXT_B = "회색 점퍼 남성을 찾습니다", "빨간 패딩 남성을 찾습니다"


@pytest.fixture
def by_text(monkeypatch):
    """문장별로 다른 결과를 주는 가짜 Gemini. gates[문장]이 있으면 열릴 때까지 기다린다."""
    class Fake:
        calls, gates = [], {}

        def __call__(self, text):
            self.calls.append(text)
            if text in self.gates:
                self.gates[text].wait(5)
            return {**FAKE_OUT, "summary": [text[:5]]}
    fake = Fake()
    fake.calls, fake.gates = [], {}
    monkeypatch.setattr(ai_features, "_call_gemini", fake)
    return fake


@pytest.fixture
def text_of(monkeypatch):
    """경보별 보낼 문장을 테스트에서 바꿀 수 있게 (문자 내용 갱신 흉내)."""
    texts = {}
    monkeypatch.setattr(ai_features, "source_text", lambda raw: texts.get(raw["msspsnIdntfccd"]))
    return texts


def summary(sid):
    return ai_features.view(sid)["summary"]


def test_late_old_result_does_not_overwrite_newer(by_text, text_of, logs):
    """A 시작 → B 시작 → B 먼저 완료(캐시) → A 늦게 완료 → 최종 결과는 B."""
    with TestClient(app):
        text_of[1] = TEXT_B
        ai_features.submit([{"msspsnIdntfccd": 1}])  # B를 미리 추출해 캐시에 둠 (다른 경보)
        assert wait_until(lambda: summary(1) == [TEXT_B[:5]])

        by_text.gates[TEXT_A] = threading.Event()
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])  # 요청 A 시작 (멈춰 있음)
        assert wait_until(lambda: TEXT_A in by_text.calls)
        text_of[2] = TEXT_B
        ai_features.submit([{"msspsnIdntfccd": 2}])  # 요청 B: 캐시에 있어 바로 완료
        assert summary(2) == [TEXT_B[:5]]
        by_text.gates[TEXT_A].set()  # A가 늦게 완료
        assert wait_until(lambda: not ai_features._waiting)
        assert ai_features.view(2)["status"] == "done" and summary(2) == [TEXT_B[:5]]  # B 유지
    assert any("새 요청이 있어 반영하지 않았습니다" in m for m in logs)
    assert any(k for k, (_, r) in ai_features._cache.items() if r["summary"] == [TEXT_A[:5]])  # 버린 결과도 캐시에


def test_old_result_waits_for_newer_request(by_text, text_of):
    """A 진행 중 B 요청(캐시 없음) → A가 끝나도 pending 유지 → B 완료 후 B."""
    with TestClient(app):
        by_text.gates[TEXT_A], by_text.gates[TEXT_B] = threading.Event(), threading.Event()
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])
        assert wait_until(lambda: TEXT_A in by_text.calls)
        text_of[2] = TEXT_B
        ai_features.submit([{"msspsnIdntfccd": 2}])
        by_text.gates[TEXT_A].set()
        assert wait_until(lambda: TEXT_B in by_text.calls)  # A는 끝났고 B 진행 중
        assert ai_features.view(2)["status"] == "pending"  # A 결과로 덮지 않음
        by_text.gates[TEXT_B].set()
        assert wait_until(lambda: ai_features.view(2)["status"] == "done")
        assert summary(2) == [TEXT_B[:5]]


def test_text_removed_while_running_keeps_unavailable(by_text, text_of):
    """진행 중에 보낼 글이 없어지면(예: AI 끔) 늦게 끝난 결과를 반영하지 않는다."""
    with TestClient(app):
        by_text.gates[TEXT_A] = threading.Event()
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])
        assert wait_until(lambda: TEXT_A in by_text.calls)
        del text_of[2]
        ai_features.submit([{"msspsnIdntfccd": 2}])
        by_text.gates[TEXT_A].set()
        assert wait_until(lambda: not ai_features._waiting)
        assert ai_features.view(2)["status"] == "unavailable"


def test_same_key_twice_calls_once_and_applies(by_text, text_of):
    with TestClient(app):
        by_text.gates[TEXT_A] = threading.Event()
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])
        assert wait_until(lambda: TEXT_A in by_text.calls)
        ai_features.submit([{"msspsnIdntfccd": 2}])  # 같은 문장으로 다시 요청 (진행 중)
        by_text.gates[TEXT_A].set()
        assert wait_until(lambda: ai_features.view(2)["status"] == "done")
        ai_features.submit([{"msspsnIdntfccd": 2}])  # 끝난 뒤 또 요청 → 캐시
    assert by_text.calls.count(TEXT_A) == 1
    assert summary(2) == [TEXT_A[:5]]
    check_shape(ai_features.view(2), full=True)


def test_back_to_first_text_applies_first_and_drops_middle(by_text, text_of):
    """A 진행 중 → B 요청 → 다시 A 요청 → A 완료는 반영, 나중에 끝난 B는 버림."""
    with TestClient(app):
        by_text.gates[TEXT_A] = threading.Event()
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])
        assert wait_until(lambda: TEXT_A in by_text.calls)
        text_of[2] = TEXT_B
        ai_features.submit([{"msspsnIdntfccd": 2}])
        text_of[2] = TEXT_A
        ai_features.submit([{"msspsnIdntfccd": 2}])
        by_text.gates[TEXT_A].set()
        assert wait_until(lambda: TEXT_B in by_text.calls and not ai_features._waiting)
        assert ai_features.view(2)["status"] == "done" and summary(2) == [TEXT_A[:5]]
    assert by_text.calls.count(TEXT_A) == 1
