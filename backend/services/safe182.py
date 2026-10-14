"""안전Dream 실종경보 실제 데이터 (DATA_SOURCE=safe182).

sample_data와 같은 모양(SOURCE, IS_SAMPLE, load_alerts, status_of)을 갖춘다.
목록은 services/sync.py가 주기적으로 받아 메모리에 둔 것을 돌려준다.
오류가 나도 키, 요청 내용, 응답 본문은 메시지에 넣지 않는다.
"""
import requests

SOURCE = "자료 출처: 경찰청"
IS_SAMPLE = False

URL = "https://www.safe182.go.kr/api/lcm/amberList.do"
ROW_SIZE = 100  # 이 API가 한 번에 주는 최대 건수 (100 초과 요청은 결과 코드 99)
RESULT_DAILY_LIMIT = "80"  # 일일 호출 한도 초과


class Safe182Error(Exception):
    """사람이 읽을 안내 문구만 담는다 (키·URL·응답 본문 없음)."""


class DailyLimitExceeded(Safe182Error):
    pass


def normalize_id(value):
    """식별번호를 정수로. 문자열("9990005", " 0009990006 ")도 받는다. 안 되면 None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


def _request_page(api_id, api_key, page):
    try:
        r = requests.post(URL, data={"esntlId": api_id, "authKey": api_key, "rowSize": ROW_SIZE, "page": page}, timeout=30)
    except requests.RequestException:
        # 예외 메시지에 요청 정보가 담길 수 있어 예외를 그대로 쓰지 않는다
        raise Safe182Error("안전Dream API 요청에 실패했습니다 (네트워크 또는 키 확인)") from None
    if r.status_code != 200:
        raise Safe182Error(f"안전Dream API가 HTTP {r.status_code} 오류를 돌려줬습니다")
    try:
        j = r.json()
    except ValueError:
        raise Safe182Error(f"안전Dream API 응답이 JSON이 아닙니다 (HTTP {r.status_code})") from None
    if not isinstance(j, dict) or "result" not in j:
        raise Safe182Error("안전Dream API 응답에 result가 없습니다")
    if j["result"] == RESULT_DAILY_LIMIT:
        raise DailyLimitExceeded("안전Dream API 일일 호출 한도를 넘었습니다 (결과 코드 80)")
    if j["result"] != "00":
        raise Safe182Error(f"안전Dream API가 결과 코드 {j['result']}를 돌려줬습니다")
    if not isinstance(j.get("totalCount"), int):
        raise Safe182Error("안전Dream API 응답에 totalCount(숫자)가 없습니다")
    rows = j.get("list")
    if rows is not None and not isinstance(rows, list):
        raise Safe182Error("안전Dream API 응답의 list가 목록이 아닙니다")
    return rows or [], j["totalCount"]


def fetch_all(api_id, api_key, count_call):
    """모든 페이지를 받는다. 페이지마다 count_call()을 부른다.

    돌려주는 값: (정상 항목들, 받은 원본 건수, totalCount, 건너뛴 건수)
    정상 항목은 식별번호를 정수로 바꾼 사본이다. 항목이 아니거나 식별번호가 없으면 건너뛴다.
    """
    received, total, page = [], None, 1
    while True:
        count_call()
        rows, total = _request_page(api_id, api_key, page)
        received += rows
        if not rows or len(received) >= total:
            break
        page += 1

    items, skipped = {}, 0
    for raw in received:
        sid = normalize_id(raw.get("msspsnIdntfccd")) if isinstance(raw, dict) else None
        if sid is None:
            skipped += 1
            continue
        items.setdefault(sid, {**raw, "msspsnIdntfccd": sid})  # 같은 번호가 두 번 오면 처음 것만
    return list(items.values()), len(received), total, skipped


def load_alerts():
    from services import sync  # 순환 import 방지
    return sync.TRACKER.snapshot()


def status_of(raw):
    from services import sync
    return sync.TRACKER.status_of(raw["msspsnIdntfccd"])
