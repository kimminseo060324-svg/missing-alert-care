"""카카오 로컬 API 주소 검색으로 주소 → 좌표 변환 수동 확인 스크립트. (pytest 테스트 아님)

가상 데이터에 쓸 실제 동 이름(한신대학교 오산캠퍼스 근처)이 좌표로 바뀌는지 확인한다.
한신대 도로명 주소를 기준점으로 두고, 각 동까지 직선거리도 출력한다.
키는 .env의 KAKAO_REST_API_KEY에서만 읽고 출력하지 않는다.
실행 (저장소 폴더에서): python backend/scripts/check_kakao_geocode.py
"""
import os
import math

import requests
from dotenv import load_dotenv, find_dotenv

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


class GeocodeError(Exception):
    pass


def km(a, b):
    """두 (x=경도, y=위도) 사이 직선거리(km), 하버사인 공식."""
    (x1, y1), (x2, y2) = [(math.radians(float(p[0])), math.radians(float(p[1]))) for p in (a, b)]
    h = math.sin((y2 - y1) / 2) ** 2 + math.cos(y1) * math.cos(y2) * math.sin((x2 - x1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def geocode(key, query):
    """(total_count, documents)를 돌려준다. 실패하면 원인을 담은 GeocodeError를 낸다."""
    try:
        r = requests.get(URL, headers={"Authorization": f"KakaoAK {key}"}, params={"query": query}, timeout=10)
    except requests.RequestException as e:
        raise GeocodeError(f"카카오 서버에 연결하지 못했습니다 ({type(e).__name__})") from None
    try:
        j = r.json()
    except ValueError:
        raise GeocodeError(f"HTTP {r.status_code}: JSON이 아닌 응답을 받았습니다 "
                           f"(content-type: {r.headers.get('content-type', '없음')}, {len(r.content)}바이트)") from None
    if r.status_code == 200:
        return j["meta"]["total_count"], j["documents"]
    msg = j.get("message", "")  # 오류 본문에는 키가 없지만, 메시지 필드만 쓴다
    if r.status_code == 401:
        raise GeocodeError(f"HTTP 401: 키가 올바르지 않습니다. .env의 KAKAO_REST_API_KEY가 REST API 키인지 확인하세요 ({msg})")
    if r.status_code == 403 and "OPEN_MAP_AND_LOCAL" in msg:
        raise GeocodeError("HTTP 403: 카카오맵(지도·로컬) 사용 설정이 꺼져 있습니다. "
                           f"카카오 디벨로퍼스 → 내 애플리케이션 → 제품 설정 → 카카오맵에서 켜 주세요 ({msg})")
    raise GeocodeError(f"HTTP {r.status_code}: {msg or '오류 메시지 없음'}")


def describe(kind, query, total, docs, base=None):
    d = docs[0]
    dist = f" | 한신대에서 {km(base, (d['x'], d['y'])):.1f}km" if base else ""
    return f"[{kind}] {query} → {total}건 | 1순위: {d['address_name']} ({d['address_type']}) x={d['x']} y={d['y']}{dist}"


def main():
    load_dotenv(find_dotenv(usecwd=True))  # 실행 위치에서 위로 올라가며 .env를 찾는다
    key = os.getenv("KAKAO_REST_API_KEY")
    if not key:
        raise SystemExit("[오류] KAKAO_REST_API_KEY가 없습니다. 저장소 폴더에서 실행했는지, .env에 키가 있는지 확인하세요.")

    kind, query = BASE
    try:
        total, docs = geocode(key, query)
    except GeocodeError as e:
        raise SystemExit(f"[오류] 기준점 조회 실패로 멈춥니다 (거리 계산 안 함): {query} → {e}")
    if not docs:
        raise SystemExit(f"[오류] 기준점 조회 결과가 없어 멈춥니다 (거리 계산 안 함): {query}")
    print(describe(kind, query, total, docs))
    base = (docs[0]["x"], docs[0]["y"])

    for kind, query in ADDRESSES:
        try:
            total, docs = geocode(key, query)
        except GeocodeError as e:
            print(f"[{kind}] {query} → {e}")
            continue
        print(describe(kind, query, total, docs, base) if docs else f"[{kind}] {query} → 결과 없음 (total_count={total})")


if __name__ == "__main__":
    main()
