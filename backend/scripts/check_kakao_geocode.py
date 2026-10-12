"""카카오 로컬 API 주소 검색으로 주소 → 좌표 변환 수동 확인 스크립트. (pytest 테스트 아님)

가상 데이터에 쓸 실제 동 이름(한신대학교 오산캠퍼스 근처)이 좌표로 바뀌는지 확인한다.
한신대 도로명 주소를 기준점으로 두고, 각 동까지 직선거리도 출력한다.
키는 저장소 루트 .env의 KAKAO_REST_API_KEY에서만 읽는다.
오류가 나도 API 키, 요청 URL·헤더(Authorization에 키가 있음), 응답 본문은 출력하지 않는다.
실행: python backend/scripts/check_kakao_geocode.py
"""
import os
import math
from pathlib import Path

import requests
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parents[2] / ".env"  # 저장소 루트의 .env만 읽는다
URL = "https://dapi.kakao.com/v2/local/search/address.json"
DOC_FIELDS = {"x", "y", "address_name", "address_type"}  # 이 스크립트가 쓰는 documents 필드

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
    except requests.RequestException:
        # 예외 메시지·요청 정보에 키가 담길 수 있어 예외를 출력하지 않는다
        raise GeocodeError("카카오 API 요청에 실패했습니다. 네트워크와 API 키를 확인해주세요.") from None
    try:
        j = r.json()
    except ValueError:
        raise GeocodeError(f"카카오 API 응답이 JSON이 아닙니다. (HTTP {r.status_code}, "
                           f"content-type: {r.headers.get('content-type', '없음')})") from None
    if r.status_code == 401:
        raise GeocodeError("HTTP 401: 키가 올바르지 않습니다. .env의 KAKAO_REST_API_KEY가 REST API 키인지 확인해주세요.")
    # 403 원인 구분에만 message를 읽고, 출력하지는 않는다
    if r.status_code == 403 and "OPEN_MAP_AND_LOCAL" in str(j.get("message", "") if isinstance(j, dict) else ""):
        raise GeocodeError("HTTP 403: 카카오맵(지도·로컬) 사용 설정이 꺼져 있습니다. "
                           "카카오 디벨로퍼스 → 내 애플리케이션 → 제품 설정 → 카카오맵에서 켜 주세요.")
    if r.status_code != 200:
        raise GeocodeError(f"카카오 API가 HTTP {r.status_code} 오류를 돌려줬습니다.")

    meta = j.get("meta") if isinstance(j, dict) else None
    docs = j.get("documents") if isinstance(j, dict) else None
    if not isinstance(meta, dict) or not isinstance(meta.get("total_count"), int):
        raise GeocodeError("카카오 API 응답에 meta.total_count(숫자)가 없습니다. 응답 형식이 바뀌었는지 확인해주세요.")
    if not (isinstance(docs, list) and all(isinstance(d, dict) for d in docs)):
        raise GeocodeError("카카오 API 응답에 documents 목록이 없습니다. 응답 형식이 바뀌었는지 확인해주세요.")
    missing = sorted({f for d in docs for f in DOC_FIELDS if f not in d})
    if missing:
        raise GeocodeError(f"카카오 API 응답의 documents에 필요한 필드가 없습니다: {', '.join(missing)}")
    if not all(is_number(d["x"]) and is_number(d["y"]) for d in docs):
        raise GeocodeError("카카오 API 응답의 좌표(x, y)가 숫자가 아니거나 비어 있습니다. 응답 형식이 바뀌었는지 확인해주세요.")
    return meta["total_count"], docs


def is_number(v):
    """좌표 값이 유한한 숫자(또는 숫자 문자열)인지. null·빈 문자열·nan·inf는 아니다."""
    if isinstance(v, bool):
        return False
    try:
        return math.isfinite(float(v))
    except (TypeError, ValueError):
        return False


def describe(kind, query, total, docs, base=None):
    d = docs[0]
    dist = f" | 한신대에서 {km(base, (d['x'], d['y'])):.1f}km" if base else ""
    return f"[{kind}] {query} → {total}건 | 1순위: {d['address_name']} ({d['address_type']}) x={d['x']} y={d['y']}{dist}"


def main():
    load_dotenv(ENV_PATH)
    key = os.getenv("KAKAO_REST_API_KEY")
    if not key:
        raise SystemExit("[오류] KAKAO_REST_API_KEY가 없습니다. 저장소 루트의 .env에 키를 넣어주세요.")

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
            raise SystemExit(f"[오류] 조회 실패로 멈춥니다: {query} → {e}")
        print(describe(kind, query, total, docs, base) if docs else f"[{kind}] {query} → 결과 없음 (total_count={total})")


if __name__ == "__main__":
    main()
