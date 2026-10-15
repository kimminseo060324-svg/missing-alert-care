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
    assert title == "실종경보"
    assert body == "오산시에서 82세 남성을 찾고 있어요\n인상: 82세 남성\n장소: 경기 오산시 양산동 123"  # 키 없음, AI 없음
    assert data == {"type": "missing_alert", "event": "issued", "alert_id": "9990001", "status": "수색중",
                    "region": "오산시", "version": "2", "title": title, "body": body, "ai_summary": "",
                    "height": "", "address": "경기 오산시 양산동 123", "age": "82", "sex": "남자"}  # 좌표 없으면 lat/lng 없음
    assert "홍길동" not in title + body + str(data)


def test_issued_fallback_and_closed_text():
    _, body, _ = push.build("issued", {"msspsnIdntfccd": 1, "occrAdres": "경기 오산시 궐동"}, "수색중")
    assert body == "오산시에서 실종자를 찾고 있어요\n장소: 경기 오산시 궐동"
    title, body, data = push.build("closed", {"msspsnIdntfccd": 1}, "경보종료")
    assert (title, body) == ("실종경보 종료", "지역 미확인 실종경보가 종료됐어요")
    assert data["event"] == "closed" and data["status"] == "경보종료"


DATA_KEYS = {"type", "event", "alert_id", "status", "region", "version",
             "title", "body", "ai_summary", "height", "address", "age", "sex"}


def test_closed_text_by_status():
    raw = {"msspsnIdntfccd": 9990001, "nm": "홍길동", "occrAdres": "경기 오산시 양산동"}
    ended = push.build("closed", raw, "경보종료")
    found = push.build("closed", raw, "발견완료")
    assert ended[:2] == ("실종경보 종료", "오산시 실종경보가 종료됐어요")
    assert found[:2] == ("실종자 발견", "오산시 실종자를 찾았어요")
    assert set(ended[2]) == set(found[2]) == DATA_KEYS
    assert "\n" not in ended[1] + found[1]  # closed는 한 줄 그대로
    assert found[2]["event"] == "closed" and found[2]["status"] == "발견완료"


def test_android_tag_same_for_issued_and_closed(monkeypatch):
    from firebase_admin import messaging
    got = []
    monkeypatch.setattr(messaging, "send", lambda msg, app=None: got.append(msg) or "id")
    raw = {"msspsnIdntfccd": 9990001, "occrAdres": "경기 오산시 양산동"}
    for event, status in [("issued", "수색중"), ("closed", "경보종료"), ("closed", "발견완료")]:
        push._send_message(*push.build(event, raw, status))
    assert [m.android.notification.tag for m in got] == ["alert_9990001"] * 3
    assert all(m.android.notification.channel_id == "missing_alerts" and m.android.priority == "high" for m in got)


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


# 발송 타임아웃 -------------------------------------------------------------------

@pytest.mark.parametrize("value, expected", [(None, 10), ("", 10), ("abc", 10), ("0", 10), ("121", 10),
                                             ("5", 5), ("2.5", 2.5), ("120", 120)])
def test_send_timeout(monkeypatch, value, expected):
    if value is None:
        monkeypatch.delenv("FIREBASE_SEND_TIMEOUT_SEC", raising=False)
    else:
        monkeypatch.setenv("FIREBASE_SEND_TIMEOUT_SEC", value)
    assert push.send_timeout() == expected


@pytest.fixture
def fake_key(tmp_path):
    """가짜 서비스 계정 파일 (테스트용으로 만든 키, 실제 프로젝트와 무관)."""
    import json
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    pem = rsa.generate_private_key(public_exponent=65537, key_size=2048).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
    path = tmp_path / "fake-key.json"
    path.write_text(json.dumps({"type": "service_account", "project_id": "fake-project", "private_key_id": "x",
                                "private_key": pem, "client_email": "fake@fake-project.iam.gserviceaccount.com",
                                "client_id": "1", "token_uri": "https://oauth2.googleapis.com/token"}))
    yield path
    import firebase_admin
    if push._app:
        firebase_admin.delete_app(push._app)


@pytest.mark.parametrize("env, expected", [(None, 10), ("3", 3)])
def test_timeout_reaches_sdk_messaging_client(monkeypatch, fake_key, env, expected):
    from firebase_admin import messaging
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT_PATH", str(fake_key))
    if env is None:
        monkeypatch.delenv("FIREBASE_SEND_TIMEOUT_SEC", raising=False)
    else:
        monkeypatch.setenv("FIREBASE_SEND_TIMEOUT_SEC", env)
    assert push.init() is True
    assert push._app.options.get("httpTimeout") == expected
    assert messaging._get_messaging_service(push._app)._client.timeout == expected  # 실제 발송에 쓰는 HTTP 클라이언트


def test_timeout_is_failed_and_sync_retries(run, fcm, monkeypatch):
    from firebase_admin import exceptions

    def slow(title, body, data):
        raise exceptions.DeadlineExceededError("Timed out while making an API call: SECRET-BODY")
    run(BASE)
    monkeypatch.setattr(push, "_send_message", slow)
    run(BASE + [row(4)])
    a = run.tracker.alerts[4]
    assert a["notified"] is False and a["push"] == "issued"  # 재전송 대상 유지
    assert push.send("issued", {"msspsnIdntfccd": 4}, "수색중") == {
        "status": "failed", "reason": "응답 시간 초과(10초, DeadlineExceededError(DEADLINE_EXCEEDED))", "message_id": None}
    monkeypatch.setattr(push, "_send_message", fcm)
    run(BASE + [row(4)])
    assert a["notified"] is True and a["push"] is None



def test_timeout_after_sdk_retry_is_labeled(fcm, monkeypatch):
    """실제 SDK는 읽기 시간 초과를 한 번 재시도한 뒤 UnavailableError로 감싸서 낸다 (원인: MaxRetryError → ReadTimeoutError)."""
    import requests
    import urllib3
    from firebase_admin import exceptions

    def wrapped(cause):
        def raise_(title, body, data):
            raise exceptions.UnavailableError("Failed to establish a connection: SECRET-BODY",
                                              cause=requests.ConnectionError(cause))
        return raise_
    timeout = urllib3.exceptions.MaxRetryError(None, "/x", urllib3.exceptions.ReadTimeoutError(None, "/x", "t"))
    monkeypatch.setattr(push, "_send_message", wrapped(timeout))
    res = push.send("issued", {"msspsnIdntfccd": 1}, "수색중")
    assert res["status"] == "failed" and res["reason"].startswith("응답 시간 초과(10초")
    refused = urllib3.exceptions.MaxRetryError(None, "/x", urllib3.exceptions.NewConnectionError(None, "refused"))
    monkeypatch.setattr(push, "_send_message", wrapped(refused))
    assert push.send("issued", {"msspsnIdntfccd": 1}, "수색중")["reason"] == "UnavailableError(UNAVAILABLE)"

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
    key = (9990001, "issued", "수색중")
    monkeypatch.setitem(push._last_fire, key, push._last_fire[key] - push.FIRE_DEDUP_SEC)
    assert client.post("/test/fire/9990001").json()["push"]["status"] == "sent"


def test_found_sends_closed(client, fcm):
    res = client.post("/test/found/9990003").json()["push"]
    assert res["status"] == "sent"
    title, body, data = fcm.sent[0]
    assert title == "실종자 발견" and data["event"] == "closed" and data["status"] == "발견완료"
    again = client.post("/test/found/9990003").json()["push"]
    assert again["status"] == "skipped" and "60초" in again["reason"]
    assert len(fcm.sent) == 1


def test_end_sends_closed_once_per_minute(client, fcm):
    client.post("/test/fire/9990001")  # issued를 보낸 직후여도 closed는 따로 센다
    res = client.post("/test/end/9990001").json()["push"]
    assert res["status"] == "sent"
    title, _, data = fcm.sent[-1]
    assert title == "실종경보 종료" and data["event"] == "closed" and data["status"] == "경보종료"
    again = client.post("/test/end/9990001").json()["push"]
    assert again["status"] == "skipped" and "60초" in again["reason"]
    assert len(fcm.sent) == 2

def test_dedup_same_status_repeat_is_skipped(client, fcm):
    assert client.post("/test/end/9990001").json()["push"]["status"] == "sent"
    again = client.post("/test/end/9990001").json()["push"]
    assert again["status"] == "skipped" and "60초" in again["reason"]
    assert client.post("/test/found/9990002").json()["push"]["status"] == "sent"
    assert client.post("/test/found/9990002").json()["push"]["status"] == "skipped"
    assert len(fcm.sent) == 2


def test_end_then_found_sends_both(client, fcm):
    assert client.post("/test/end/9990001").json()["push"]["status"] == "sent"
    assert client.post("/test/found/9990001").json()["push"]["status"] == "sent"  # 경보종료→발견완료는 상태가 달라 발송
    assert [(t, d["status"]) for t, _, d in fcm.sent] == [("실종경보 종료", "경보종료"), ("실종자 발견", "발견완료")]


def test_failed_send_is_not_recorded_and_retries(client, fcm):
    fcm.fail = True
    assert client.post("/test/end/9990001").json()["push"]["status"] == "failed"
    assert push._last_fire == {}  # 실패는 중복 방지 키에 기록 안 됨
    fcm.fail = False
    assert client.post("/test/end/9990001").json()["push"]["status"] == "sent"  # 바로 다시 불러도 재시도
    assert list(push._last_fire) == [(9990001, "closed", "경보종료")]

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



# 여러 줄 본문·data 확장·data-only -------------------------------------------------------

RICH = {"msspsnIdntfccd": 9990001, "nm": "홍길동", "ageNow": "82", "sexdstnDscd": "남자", "height": 168,
        "occrAdres": "경기 오산시 양산동"}


def set_ai(monkeypatch, sid, status, summary):
    from services import ai_features
    r = {**ai_features._empty(status), "summary": summary}
    monkeypatch.setitem(ai_features._results, sid, r)


def test_issued_body_four_lines_when_ai_done(monkeypatch):
    set_ai(monkeypatch, 9990001, "done", ["회색 점퍼", "검정 바지", "지팡이 사용"])
    _, body, data = push.build("issued", RICH, "수색중")
    assert body.split("\n") == ["오산시에서 82세 남성을 찾고 있어요", "옷차림: 회색 점퍼 · 검정 바지 · 지팡이 사용",
                                 "인상: 82세 남성 · 168cm", "장소: 경기 오산시 양산동"]
    assert data["ai_summary"] == "회색 점퍼 · 검정 바지 · 지팡이 사용"
    assert (data["height"], data["address"], data["age"], data["sex"]) == ("168", "경기 오산시 양산동", "82", "남자")
    assert data["body"] == body and data["title"] == "실종경보"
    assert "홍길동" not in body + str(data)


@pytest.mark.parametrize("status", ["pending", "unavailable"])
def test_issued_body_three_lines_without_ai(monkeypatch, status):
    set_ai(monkeypatch, 9990001, status, [])
    _, body, data = push.build("issued", RICH, "수색중")
    assert body.split("\n") == ["오산시에서 82세 남성을 찾고 있어요", "인상: 82세 남성 · 168cm", "장소: 경기 오산시 양산동"]
    assert data["ai_summary"] == ""


def test_done_with_empty_summary_has_no_clothing_line(monkeypatch):
    set_ai(monkeypatch, 9990001, "done", [])
    assert "옷차림" not in push.build("issued", RICH, "수색중")[1]


@pytest.mark.parametrize("height, line", [(None, "인상: 82세 남성"), ("", "인상: 82세 남성"), (0, "인상: 82세 남성"),
                                          ("175cm", "인상: 82세 남성 · 175cm"), ("160.5", "인상: 82세 남성 · 160cm")])
def test_looks_line_height(height, line):
    body = push.build("issued", {**RICH, "height": height}, "수색중")[1]
    assert body.split("\n")[1] == line


def test_missing_values_drop_lines_and_data_empty_strings():
    _, body, data = push.build("issued", {"msspsnIdntfccd": 5}, "수색중")
    assert body == "지역 미확인에서 실종자를 찾고 있어요"  # 인상·장소 줄 없음
    assert (data["height"], data["address"], data["age"], data["sex"], data["ai_summary"]) == ("", "", "", "", "")


def test_height_only_looks_line():
    body = push.build("issued", {"msspsnIdntfccd": 5, "height": 150}, "수색중")[1]
    assert body.split("\n")[1] == "인상: 150cm"


@pytest.mark.parametrize("event, status", [("issued", "수색중"), ("closed", "경보종료"), ("closed", "발견완료")])
def test_data_all_strings_version_2(monkeypatch, event, status):
    set_ai(monkeypatch, 9990001, "done", ["회색 점퍼"])
    _, _, data = push.build(event, RICH, status)
    assert set(data) == DATA_KEYS and all(isinstance(v, str) for v in data.values())
    assert data["version"] == "2"


def capture(monkeypatch):
    from firebase_admin import messaging
    got = []
    monkeypatch.setattr(messaging, "send", lambda msg, app=None: got.append(messaging._MessagingService.encode_message(msg))
                        or "id")
    return got


def test_default_mode_has_notification(monkeypatch):
    monkeypatch.delenv("PUSH_DATA_ONLY", raising=False)
    got = capture(monkeypatch)
    push._send_message(*push.build("issued", RICH, "수색중"))
    m = got[0]
    assert m["notification"]["title"] == "실종경보" and "\n" in m["notification"]["body"]
    assert m["android"]["notification"] == {"channel_id": "missing_alerts", "tag": "alert_9990001"}


@pytest.mark.parametrize("event, status", [("issued", "수색중"), ("closed", "발견완료")])
def test_data_only_mode(monkeypatch, event, status):
    monkeypatch.setenv("PUSH_DATA_ONLY", "1")
    got = capture(monkeypatch)
    title, body, _ = push.build(event, RICH, status)
    push._send_message(title, body, push.build(event, RICH, status)[2])
    m = got[0]
    assert "notification" not in m and "notification" not in m["android"]
    assert m["android"]["priority"] == "high"
    assert m["data"]["title"] == title and m["data"]["body"] == body
    assert m["topic"] == "missing_alerts_osan"


def test_data_only_keeps_dedup(client, fcm, monkeypatch):
    monkeypatch.setenv("PUSH_DATA_ONLY", "1")
    assert client.post("/test/fire/9990001").json()["push"]["status"] == "sent"
    assert client.post("/test/fire/9990001").json()["push"]["status"] == "skipped"
