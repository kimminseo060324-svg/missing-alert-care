"""행안부 긴급재난문자 API(재난안전데이터공유플랫폼 DSSP-IF-00247) 확인용 스크립트.

문자 원문에는 실제 실종자 정보가 있으므로 원문은 출력·저장하지 않고 건수와 구조만 출력한다.
실행: python backend/test_disaster_msg_api.py [조회일수, 기본 7]
"""
import os
import re
import sys
import datetime
from collections import Counter
from pathlib import Path

import requests
from dotenv import load_dotenv

URL = "https://www.safetydata.go.kr/V2/api/DSSP-IF-00247"
MAX_ROWS = 1000  # 이 API가 한 번에 주는 최대 건수 (5000 요청해도 1000건)
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7

MISSING_WORDS = ["실종", "찾습니다", "배회"]
CLOTHES = ["남방", "점퍼", "잠바", "자켓", "재킷", "패딩", "조끼", "셔츠", "상의", "하의", "바지",
           "청바지", "치마", "원피스", "슬리퍼", "운동화", "신발", "구두", "모자", "가방", "후드", "등산복"]
COLORS = ["청색", "검정", "검은", "흰색", "흰", "회색", "빨간", "빨강", "파란", "파랑", "노란", "노랑",
          "초록", "녹색", "남색", "곤색", "갈색", "베이지", "분홍", "보라", "주황", "카키", "하늘색", "곤색"]
AGE = re.compile(r"(\d{1,3})\s*세")


def fetch_since(key, start):
    """start(YYYYMMDD) 이후 문자를 모두 받아온다. 응답은 메모리에서만 다룬다."""
    rows, page = [], 1
    while True:
        r = requests.get(URL, params={"serviceKey": key, "returnType": "json", "crtDt": start,
                                      "pageNo": page, "numOfRows": MAX_ROWS}, timeout=60)
        j = r.json()
        if j["header"]["resultCode"] != "00":
            raise RuntimeError(f"API 오류 {j['header']}")
        body = j.get("body") or []
        rows += body
        if not body or len(rows) >= j["totalCount"]:
            return rows, r.headers


def has_any(text, words):
    return any(w in text for w in words)


def age_group(text):
    m = AGE.search(text)
    if not m:
        return "나이 미기재"
    age = int(m.group(1))
    return "아동(18세 미만)" if age < 18 else "노인(65세 이상)" if age >= 65 else "성인(18~64세)"


def main():
    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
    key = os.getenv("DISASTER_MSG_API_KEY")
    assert key, ".env에 DISASTER_MSG_API_KEY 없음"

    today = datetime.date.today()
    start = today - datetime.timedelta(days=DAYS - 1)
    rows, headers = fetch_since(key, start.strftime("%Y%m%d"))
    # crtDt는 '이후' 필터라 기간 밖 데이터가 섞일 수 있어 한 번 더 거른다
    lo = start.strftime("%Y/%m/%d")
    rows = [x for x in rows if x["CRT_DT"][:10] >= lo]

    print("== 1. 응답 구조")
    print("필드:", sorted(rows[0].keys()) if rows else "(데이터 없음)")
    print("호출 제한 관련 응답 헤더:", {k: v for k, v in headers.items() if "limit" in k.lower() or "quota" in k.lower()} or "없음")

    print(f"\n== 3. 최근 {DAYS}일({lo} ~ {today:%Y/%m/%d}) 건수")
    print("전체 문자:", len(rows), "| 고유 문구:", len({x["MSG_CN"] for x in rows}))
    for w in MISSING_WORDS:
        print(f"  '{w}' 포함:", sum(w in x["MSG_CN"] for x in rows))
    missing = [x for x in rows if has_any(x["MSG_CN"], MISSING_WORDS)]
    uniq = {x["MSG_CN"]: x for x in missing}  # 같은 문구가 여러 지역으로 발송되면 1건으로
    print("  셋 중 하나라도 포함(실종 문자):", len(missing), "| 고유 문구:", len(uniq))
    print("  실종 문자의 재난구분:", dict(Counter(x["DST_SE_NM"] for x in missing)))

    print("\n== 4. 2026-10-03 21시대 해남군 실종 문자")
    haenam = [x for x in rows if "해남" in x["RCPTN_RGN_NM"] and x["CRT_DT"].startswith("2026/10/03 21")]
    print("해남군 10/03 21시대 문자 전체:", len(haenam), "건 | 그중 실종 문자:",
          "있다" if any(has_any(x["MSG_CN"], MISSING_WORDS) for x in haenam) else "없다")

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
