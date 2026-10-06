"""카카오 로컬 API 주소 검색으로 주소 → 좌표 변환 테스트.

가상 데이터에 쓸 실제 동 이름(한신대학교 오산캠퍼스 근처)이 좌표로 바뀌는지 확인한다.
한신대 도로명 주소를 기준점(대조군)으로 두고, 각 동까지 직선거리도 출력한다.
실행: python backend/test_kakao_geocode.py
"""
import os
import math
from pathlib import Path

import requests
from dotenv import load_dotenv

URL = "https://dapi.kakao.com/v2/local/search/address.json"

BASE = ("기준점(한신대)", "경기도 오산시 한신대길 137")
ADDRESSES = [
    ("동", "경기도 오산시 양산동"),
    ("동", "경기도 오산시 세교동"),
    ("동", "경기도 오산시 금암동"),
    ("동", "경기도 오산시 수청동"),
    ("동", "경기도 오산시 궐동"),
    ("동", "경기도 오산시 내삼미동"),
    ("이전 가상 형식", "서울특별시 가상구 테스트동"),
]


def km(a, b):
    """두 (x=경도, y=위도) 사이 직선거리(km), 하버사인 공식."""
    (x1, y1), (x2, y2) = [(math.radians(float(p[0])), math.radians(float(p[1]))) for p in (a, b)]
    h = math.sin((y2 - y1) / 2) ** 2 + math.cos(y1) * math.cos(y2) * math.sin((x2 - x1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def geocode(key, query):
    r = requests.get(URL, headers={"Authorization": f"KakaoAK {key}"}, params={"query": query}, timeout=10)
    if r.status_code != 200:
        # 오류 본문에는 키가 없지만, 혹시 몰라 메시지 필드만 쓴다
        return r.status_code, None, r.json().get("message", "")
    j = r.json()
    return 200, j["meta"]["total_count"], j["documents"]


def main():
    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
    key = os.getenv("KAKAO_REST_API_KEY")
    assert key, ".env에 KAKAO_REST_API_KEY 없음"

    base = None
    for kind, query in [BASE] + ADDRESSES:
        status, total, docs = geocode(key, query)
        if status != 200:
            print(f"[{kind}] {query} → HTTP {status} {docs}")
            continue
        if not docs:
            print(f"[{kind}] {query} → 결과 없음 (total_count={total})")
            continue
        d = docs[0]
        base = base or (d["x"], d["y"])
        dist = f" | 한신대에서 {km(base, (d['x'], d['y'])):.1f}km" if (kind, query) != BASE else ""
        print(f"[{kind}] {query} → {total}건 | 1순위: {d['address_name']} ({d['address_type']}) x={d['x']} y={d['y']}{dist}")


if __name__ == "__main__":
    main()
