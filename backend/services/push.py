"""FCM 토픽 푸시 발송 (firebase-admin).

- 키 파일 경로는 .env의 FIREBASE_SERVICE_ACCOUNT_PATH (저장소 밖, 예: ~/.missing-alert-care/...).
  경로가 없거나 파일이 없거나 읽지 못하면 푸시만 끄고 로그 한 줄을 남긴다. 서버는 그대로 돈다.
- 키 내용, 키 경로, 예외 메시지, 응답 본문은 로그·응답에 넣지 않는다 (예외는 종류와 코드만).
- 알림 문구와 data에는 실명·상세 주소를 넣지 않는다 (시·군·구, 나이, 성별만).
- send()는 {"status": "sent"|"skipped"|"failed", "reason", "message_id"}를 돌려준다.
- 발송 타임아웃은 .env FIREBASE_SEND_TIMEOUT_SEC (기본 10초). firebase-admin 앱 옵션 httpTimeout에
  초 단위로 넘긴다 (SDK 문서: "httpTimeout ... default timeout of 120 seconds", 인증 토큰 갱신에도 같은 값).
  타임아웃은 HTTP 요청 한 번마다 걸리고, SDK가 안에서 다시 보내는 요청에도 각각 걸린다.
- SDK 내부 재시도 (firebase-admin 7.7.0 _http_client.DEFAULT_RETRY_CONFIG, urllib3 2.8.0으로 확인):
  500·503 응답은 최대 4번 다시 보내고 사이 대기는 0·1·2·4초. 503에 Retry-After 헤더가 있으면 그 값만큼 기다린다
  (urllib3 상한 21600초). 읽기 시간 초과·연결 시간 초과는 각각 1번 다시 보낸다.
  그래서 send() 한 번은 타임아웃보다 길어질 수 있다 (예: 503만 계속 오면 요청 5번 + 대기 약 7초).
- 재시도 뒤에도 시간 초과면 UnavailableError(UNAVAILABLE)로, 재시도 없이 끝나면 DeadlineExceededError로 온다.
  둘 다 원인을 따라가 "응답 시간 초과"로 표시하고 failed로 돌려준다 (sync는 재전송 대상으로 남긴다).
- 같은 경보에서 issued·closed 알림은 tag "alert_{식별번호}"를 같이 써서 기기에서 한 알림으로 바뀐다.
"""
import logging
import os
import threading
import time
from pathlib import Path

TOPIC = "missing_alerts_osan"
CHANNEL_ID = "missing_alerts"
DATA_VERSION = "1"
DEFAULT_SEND_TIMEOUT = 10.0  # 초 (FIREBASE_SEND_TIMEOUT_SEC)
FIRE_DEDUP_SEC = 60  # 시연용 API로 같은 경보·같은 종류(issued/closed)·같은 상태를 이 시간 안에 다시 보내지 않는다
UNKNOWN_REGION = "지역 미확인"
GENDER = {"남자": "남성", "여자": "여성", "남": "남성", "여": "여성"}
_SIDO = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원",
         "충북", "충남", "충청", "전북", "전남", "전라", "경북", "경남", "경상", "제주")

log = logging.getLogger("push")
if not log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(asctime)s [push] %(levelname)s %(message)s"))
    log.addHandler(_h)
    log.setLevel(logging.INFO)
    log.propagate = False

_lock = threading.Lock()
_app = None
_disabled = None  # 끈 이유. None이면 아직 init() 전
_last_fire = {}  # (식별번호, event, status) → 마지막 발송 성공 시각 (time.monotonic). 실패는 기록하지 않는다


def send_timeout():
    """FIREBASE_SEND_TIMEOUT_SEC (1~120초). 비었거나 숫자가 아니거나 범위 밖이면 기본 10초."""
    try:
        sec = float((os.getenv("FIREBASE_SEND_TIMEOUT_SEC") or "").strip())
    except ValueError:
        return DEFAULT_SEND_TIMEOUT
    return sec if 1 <= sec <= 120 else DEFAULT_SEND_TIMEOUT


def init():
    """한 번만 준비한다. 성공하면 True. 실패하면 이유를 남기고 False (다시 시도하지 않음)."""
    global _app, _disabled
    with _lock:
        if _app or _disabled:
            return _app is not None
        path = (os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH") or "").strip()
        if not path:
            _disabled = "FIREBASE_SERVICE_ACCOUNT_PATH가 없어 푸시를 끕니다"
        elif not Path(path).expanduser().is_file():
            _disabled = "FIREBASE_SERVICE_ACCOUNT_PATH의 키 파일이 없어 푸시를 끕니다"
        else:
            try:
                import firebase_admin
                from firebase_admin import credentials
                cred = credentials.Certificate(str(Path(path).expanduser()))
                _app = firebase_admin.initialize_app(cred, {"httpTimeout": send_timeout()}, name="missing-alert-push")
            except Exception as e:  # 메시지에 키 일부가 담길 수 있어 종류만 쓴다
                _disabled = f"키 파일을 읽지 못해 푸시를 끕니다 ({type(e).__name__})"
        if _app:
            log.info("FCM 푸시 준비 완료 (토픽 %s, 발송 타임아웃 %g초)", TOPIC, send_timeout())
            return True
        log.warning(_disabled)
        return False


def region_of(address):
    """발생 주소 → 시·군·구 ("경기 오산시 양산동" → "오산시", "경기 수원시 영통구 …" → "수원시 영통구").
    시·군·구가 없으면(세종 등) 시·도, 그것도 없으면 "지역 미확인"."""
    tokens = (address or "").split()
    sido = None
    if tokens and tokens[0].startswith(_SIDO) and (
            len(tokens[0]) <= 2 or tokens[0].endswith(("특별시", "광역시", "특별자치시", "도"))):
        sido = tokens.pop(0)
    parts = []
    for t in tokens:
        if not t.endswith(("시", "군", "구")):
            break
        parts.append(t)
    return " ".join(parts) or sido or UNKNOWN_REGION


def coordinates(raw):
    """경보 위치 (lat, lng). 지오코딩은 아직 없어 None (그러면 data에 lat/lng를 넣지 않는다)."""
    return None


def _age(raw):
    for key in ("ageNow", "age"):
        text = str(raw.get(key) or "").strip()
        if text.isdigit() and int(text) > 0:
            return int(text)
    return None


def build(event, raw, status):
    """(제목, 본문, data). data 값은 모두 문자열."""
    region = region_of(raw.get("occrAdres"))
    if event == "closed" and status == "발견완료":
        title, body = "실종자 발견", f"{region} 실종자를 찾았어요"
    elif event == "closed":
        title, body = "실종경보 종료", f"{region} 실종경보가 종료됐어요"
    else:
        age, gender = _age(raw), GENDER.get(str(raw.get("sexdstnDscd") or "").strip())
        title = "실종경보"
        body = f"{region}에서 {age}세 {gender}을 찾고 있어요" if age and gender else f"{region}에서 실종자를 찾고 있어요"
    data = {"type": "missing_alert", "event": event, "alert_id": str(raw.get("msspsnIdntfccd", "")),
            "status": str(status), "region": region, "version": DATA_VERSION}
    point = coordinates(raw)
    if point:
        data["lat"], data["lng"] = str(point[0]), str(point[1])
    return title, body, data


def _send_message(title, body, data):
    """실제 발송. 메시지 ID를 돌려준다. 테스트에서는 이 함수를 바꿔 끼운다."""
    from firebase_admin import messaging
    msg = messaging.Message(
        topic=TOPIC,
        notification=messaging.Notification(title=title, body=body),
        data=data,
        android=messaging.AndroidConfig(priority="high", notification=messaging.AndroidNotification(
            channel_id=CHANNEL_ID, tag=f"alert_{data['alert_id']}")),  # 같은 경보의 issued·closed는 한 알림으로 바뀜
    )
    return messaging.send(msg, app=_app)


def _is_timeout(e):
    """FCM 예외가 시간 초과 때문인지. firebase 예외 → requests 예외 → urllib3 MaxRetryError 순으로 원인을 따라간다."""
    import requests
    import urllib3
    for _ in range(5):
        if e is None:
            return False
        if isinstance(e, urllib3.exceptions.NewConnectionError):  # 연결 거부. urllib3에서 TimeoutError 하위라 먼저 뺀다
            return False
        if getattr(e, "code", None) == "DEADLINE_EXCEEDED" or isinstance(e, (requests.Timeout, urllib3.exceptions.TimeoutError)):
            return True
        if isinstance(e, urllib3.exceptions.MaxRetryError):
            e = e.reason
            continue
        inner = e.args[0] if e.args and isinstance(e.args[0], BaseException) else None
        e = getattr(e, "cause", None) or e.__cause__ or inner
    return False


def send(event, raw, status, dedup=False):
    """event: "issued" | "closed". dedup=True면 같은 경보·같은 event·같은 status를 FIRE_DEDUP_SEC 안에 다시 보내지 않는다."""
    key = (raw.get("msspsnIdntfccd"), event, status)
    if not init():
        return {"status": "skipped", "reason": _disabled, "message_id": None}
    if dedup:
        with _lock:
            last = _last_fire.get(key)
            if last is not None and time.monotonic() - last < FIRE_DEDUP_SEC:
                return {"status": "skipped", "reason": f"{FIRE_DEDUP_SEC}초 안에 같은 경보를 이미 보냈습니다",
                        "message_id": None}
    try:
        message_id = _send_message(*build(event, raw, status))
    except Exception as e:  # 예외 메시지에 응답 본문이 담길 수 있어 종류·코드만 쓴다
        code = getattr(e, "code", None)
        reason = f"{type(e).__name__}({code})" if code else type(e).__name__
        if _is_timeout(e):
            reason = f"응답 시간 초과({send_timeout():g}초, {reason})"
        log.warning("푸시 %s 발송 실패: %s", event, reason)
        return {"status": "failed", "reason": reason, "message_id": None}
    if dedup:
        with _lock:
            _last_fire[key] = time.monotonic()
    log.info("푸시 %s 발송 완료", event)
    return {"status": "sent", "reason": None, "message_id": message_id}
