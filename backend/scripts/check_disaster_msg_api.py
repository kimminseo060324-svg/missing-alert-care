"""행안부 긴급재난문자 API(재난안전데이터공유플랫폼 DSSP-IF-00247) 수동 확인 스크립트. (pytest 테스트 아님)

문자 원문에는 실제 실종자 정보가 있으므로 원문은 출력·저장하지 않고 건수와 구조만 출력한다.
오류가 나도 API 키, 키가 들어간 요청 URL, 응답 본문은 출력하지 않는다.
실행:
    python backend/scripts/check_disaster_msg_api.py [조회일수, 기본 7]
    python backend/scripts/check_disaster_msg_api.py 30 --region 지역이름 --date YYYY-MM-DD [HH]
"""
import os
import re
import math
import time
import argparse
import datetime
from collections import Counter
from pathlib import Path

import requests
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parents[2] / ".env"  # 저장소 루트의 .env만 읽는다
URL = "https://www.safetydata.go.kr/V2/api/DSSP-IF-00247"
ROW_FIELDS = {"SN", "CRT_DT", "MSG_CN", "RCPTN_RGN_NM", "DST_SE_NM"}  # 이 스크립트가 쓰는 필드
# 글자로 자르거나 검색하거나(CRT_DT, MSG_CN, RCPTN_RGN_NM) 개수를 세므로(DST_SE_NM) 문자열이어야 하는 필드
STR_FIELDS = ("CRT_DT", "MSG_CN", "RCPTN_RGN_NM", "DST_SE_NM")
MAX_ROWS = 1000  # 이 API가 한 번에 주는 최대 건수 (5000 요청해도 1000건)
RETRIES = 3      # 빈 본문일 때 같은 페이지를 다시 요청하는 횟수
RETRY_WAIT = 2   # 다시 요청하기 전 대기(초)

MISSING_WORDS = ["실종", "찾습니다", "배회"]
CLOTHES = ["남방", "점퍼", "잠바", "자켓", "재킷", "패딩", "조끼", "셔츠", "상의", "하의", "바지",
           "청바지", "치마", "원피스", "슬리퍼", "운동화", "신발", "구두", "모자", "가방", "후드", "등산복"]
COLORS = ["청색", "검정", "검은", "흰색", "흰", "회색", "빨간", "빨강", "파란", "파랑", "노란", "노랑",
          "초록", "녹색", "남색", "곤색", "갈색", "베이지", "분홍", "보라", "주황", "카키", "하늘색"]
AGE = re.compile(r"(\d{1,3})\s*세")
DATE_ARG = re.compile(r"\d{4}-\d{2}-\d{2}( \d{2})?")


def fail(msg):
    """키·URL·응답 본문 없이 안내 문구만 남기고 끝낸다."""
    raise SystemExit(f"[오류] {msg}")


def request_page(key, start, page):
    """한 페이지를 요청해 검사한 응답(JSON)을 돌려준다. 이상하면 알기 쉬운 문구로 끝낸다."""
    try:
        r = requests.get(URL, params={"serviceKey": key, "returnType": "json", "crtDt": start,
                                      "pageNo": page, "numOfRows": MAX_ROWS}, timeout=60)
    except requests.RequestException:
        # 예외 메시지에 serviceKey가 들어간 URL이 담길 수 있어 예외를 출력하지 않는다
        fail("재난문자 API 요청에 실패했습니다. 네트워크와 API 키를 확인해주세요.")
    if r.status_code != 200:
        fail(f"재난문자 API가 HTTP {r.status_code} 오류를 돌려줬습니다.")
    try:
        j = r.json()
    except ValueError:
        fail(f"재난문자 API 응답이 JSON이 아닙니다. (HTTP {r.status_code}, content-type: {r.headers.get('content-type', '없음')})")

    header = j.get("header") if isinstance(j, dict) else None
    if not isinstance(header, dict) or "resultCode" not in header:
        fail("재난문자 API 응답에 header.resultCode가 없습니다. 응답 형식이 바뀌었는지 확인해주세요.")
    if header["resultCode"] != "00":
        fail(f"재난문자 API가 오류 코드 {header['resultCode']}를 돌려줬습니다. API 키와 요청 값을 확인해주세요.")
    if not isinstance(j.get("totalCount"), int):
        fail("재난문자 API 응답에 totalCount(숫자)가 없습니다. 응답 형식이 바뀌었는지 확인해주세요.")
    body = j.get("body")
    if body is not None and not (isinstance(body, list) and all(isinstance(x, dict) for x in body)):
        fail("재난문자 API 응답의 body가 목록 형식이 아닙니다. 응답 형식이 바뀌었는지 확인해주세요.")
    missing = sorted({f for x in body or [] for f in ROW_FIELDS if f not in x})
    if missing:
        fail(f"재난문자 API 응답에 필요한 필드가 없습니다: {', '.join(missing)}")
    # 값은 출력하지 않고 필드 이름과 건수만 알린다
    bad = Counter(f for x in body or [] for f in STR_FIELDS if not isinstance(x[f], str))
    if bad:
        fail("재난문자 API 응답에 문자열이 아니거나 비어 있는(null) 값이 있습니다: "
             + ", ".join(f"{f} {n}건" for f, n in sorted(bad.items())))
    if any(x["SN"] is None or isinstance(x["SN"], (dict, list)) for x in body or []):
        fail("재난문자 API 응답에 일련번호(SN)가 비어 있거나 형식이 맞지 않는 문자가 있습니다.")
    return j, r.headers


def fetch_page(key, start, page):
    """한 페이지 요청. 이 API는 가끔 정상 코드(00)와 함께 빈 본문을 주므로 몇 번 다시 요청한다."""
    for attempt in range(RETRIES + 1):
        if attempt:
            time.sleep(RETRY_WAIT)
        j, headers = request_page(key, start, page)
        # 본문이 있거나, 전체가 0건이라 비어 있는 게 정상이면 다시 요청하지 않는다
        if j.get("body") or j["totalCount"] == 0:
            return j.get("body") or [], j["totalCount"], headers
    return [], j["totalCount"], headers


def fetch_since(key, start):
    """start(YYYYMMDD) 이후 문자를 모두 받아온다. 응답은 메모리에서만 다룬다."""
    rows, empty, page, pages = [], [], 1, 1
    while page <= pages:
        body, total, headers = fetch_page(key, start, page)
        pages = math.ceil(total / MAX_ROWS)
        if not body and total:
            empty.append(page)
            print(f"[경고] {page}쪽이 {RETRIES}번 다시 요청해도 비어 있어 건너뜀")
        rows += body
        page += 1
    # 페이지를 받는 사이 새 문자가 들어오면 같은 문자가 두 쪽에 걸쳐 올 수 있어 SN 기준으로 하나만 남긴다
    unique = {}
    for x in rows:
        unique.setdefault(x["SN"], x)  # 처음 받은 것을 남기고 순서 유지
    if len(unique) != len(rows):
        print(f"[경고] 일련번호(SN)가 같은 중복 문자 {len(rows) - len(unique)}건을 제외했습니다")
    rows = list(unique.values())
    if len(rows) != total:
        print(f"[경고] 받은 건수 {len(rows)} ≠ totalCount {total} (빈 쪽: {empty or '없음'})")
    return rows, headers


def has_any(text, words):
    return any(w in text for w in words)


def age_group(text):
    m = AGE.search(text)
    if not m:
        return "나이 미기재"
    age = int(m.group(1))
    return "아동(18세 미만)" if age < 18 else "노인(65세 이상)" if age >= 65 else "성인(18~64세)"


def parse_args():
    p = argparse.ArgumentParser(description="긴급재난문자 API 건수·구조 확인 (원문은 출력하지 않음)")
    p.add_argument("days", nargs="?", type=int, default=7, help="최근 며칠을 조회할지 (기본 7)")
    p.add_argument("--region", help="4절: 수신지역 이름에 이 글자가 들어간 문자만 (예: 시군구 이름)")
    p.add_argument("--date", help="4절: 이 날짜(YYYY-MM-DD) 또는 날짜·시(YYYY-MM-DD HH)의 문자만")
    args = p.parse_args()
    if args.days < 1:
        p.error("조회일수(days)는 1 이상이어야 합니다")
    if args.date and not DATE_ARG.fullmatch(args.date):
        p.error("--date는 YYYY-MM-DD 또는 'YYYY-MM-DD HH' 형식이어야 합니다")
    return args


def main():
    args = parse_args()
    load_dotenv(ENV_PATH)
    key = os.getenv("DISASTER_MSG_API_KEY")
    if not key:
        raise SystemExit("[오류] DISASTER_MSG_API_KEY가 없습니다. 저장소 루트의 .env에 키를 넣어주세요.")

    today = datetime.date.today()
    start = today - datetime.timedelta(days=args.days - 1)
    rows, headers = fetch_since(key, start.strftime("%Y%m%d"))
    # crtDt는 '이후' 필터라 기간 밖 데이터가 섞일 수 있어 한 번 더 거른다
    lo = start.strftime("%Y/%m/%d")
    rows = [x for x in rows if x["CRT_DT"][:10] >= lo]

    print("== 1. 응답 구조")
    print("필드:", sorted(rows[0].keys()) if rows else "(데이터 없음)")

    print("\n== 2. 호출 제한·한 번에 받는 최대 건수")
    print("호출 제한 관련 응답 헤더:", {k: v for k, v in headers.items() if "limit" in k.lower() or "quota" in k.lower()} or "없음")
    print("한 번에 받는 최대 건수:", MAX_ROWS)

    print(f"\n== 3. 최근 {args.days}일({lo} ~ {today:%Y/%m/%d}) 건수")
    print("전체 문자:", len(rows), "| 고유 문구:", len({x["MSG_CN"] for x in rows}))
    for w in MISSING_WORDS:
        print(f"  '{w}' 포함:", sum(w in x["MSG_CN"] for x in rows))
    missing = [x for x in rows if has_any(x["MSG_CN"], MISSING_WORDS)]
    uniq = {x["MSG_CN"]: x for x in missing}  # 같은 문구가 여러 지역으로 발송되면 1건으로
    print("  셋 중 하나라도 포함(실종 문자):", len(missing), "| 고유 문구:", len(uniq))
    print("  실종 문자의 재난구분:", dict(Counter(x["DST_SE_NM"] for x in missing)))

    print("\n== 4. 지정한 지역·날짜의 실종 문자")
    if not (args.region or args.date):
        print("(건너뜀: --region 또는 --date를 주면 확인)")
    else:
        prefix = args.date.replace("-", "/") if args.date else ""
        if prefix and prefix[:10] < lo:
            print(f"[경고] --date가 조회 기간({lo}~) 밖입니다. 조회일수를 늘려 주세요.")
        sel = [x for x in rows if (not args.region or args.region in x["RCPTN_RGN_NM"]) and x["CRT_DT"].startswith(prefix)]
        print("해당 문자:", len(sel), "건 | 그중 실종 문자:", sum(has_any(x["MSG_CN"], MISSING_WORDS) for x in sel), "건")

    print("\n== 5. 실종 문자(고유 문구 기준) 옷·색깔 표현 비율")
    n = len(uniq) or 1
    c = sum(has_any(t, CLOTHES) for t in uniq)
    k = sum(has_any(t, COLORS) for t in uniq)
    e = sum(has_any(t, CLOTHES + COLORS) for t in uniq)
    print(f"옷 종류: {c}/{len(uniq)} ({c / n:.0%}) | 색깔: {k}/{len(uniq)} ({k / n:.0%}) | 둘 중 하나: {e}/{len(uniq)} ({e / n:.0%})")

    print("\n== 6. 실종 문자(고유 문구 기준) 나이대")
    groups = Counter(age_group(t) for t in uniq)
    print(dict(groups))
    adults = [t for t in uniq if age_group(t) == "성인(18~64세)"]
    print("성인 중 치매·장애 언급 없는 문자:", sum(not has_any(t, ["치매", "장애"]) for t in adults), "/", len(adults))

    print("\n== 7. 발송 시각·지역 필드")
    print("CRT_DT(생성일시) 예:", rows[0]["CRT_DT"][:16] if rows else "-", "| RCPTN_RGN_NM(수신지역) 있음:", bool(rows and rows[0].get("RCPTN_RGN_NM")))


if __name__ == "__main__":
    main()
