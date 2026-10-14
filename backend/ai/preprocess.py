"""재난문자 개인정보 제거. AI에 보내기 전에 쓴다.

redact(): 이름(○○○씨/군/양), 식별번호·긴 숫자, 전화번호, 상세 주소(번지·도로명 번호·호수·건물명)를 지운다.
          동 단위 지역, 신고 번호(☎112·☎182), 나이·키·몸무게는 남긴다.
clothing_part(): redact() 후, "…를 찾습니다." 앞부분과 끝의 신고 번호·발송 기관을 떼고 인상착의 부분만 남긴다.
"""
import re

MASK = "○○○"
_NAME = re.compile(r"[가-힣]{2,4}(?=(?:씨|군|양)(?:\(|\s|을|를|이|가|의|$))")
_PHONE = re.compile(r"(?<!\d)0\d{1,2}[-.\s]?\d{3,4}[-.\s]?\d{4}(?!\d)")
_LONG_NUMBER = re.compile(r"(?<![\d.])\d{7,}(?![\d.])")  # 식별번호 등 (키·몸무게·나이·신고번호는 7자리 미만)
_LOT = re.compile(r"(?:산\s?)?\d+(?:-\d+)?\s*번지")
_ROAD = re.compile(r"[가-힣0-9]+(?:로|길)\s*\d+(?:번길)?(?:-\d+)?(?:\s*번)?")
_UNIT = re.compile(r"\d+\s*동\s*\d+\s*호|\d+\s*호(?!선)")
_BUILDING = re.compile(r"[가-힣A-Za-z0-9]+(?:아파트|빌라|오피스텔|맨션|타워|빌딩|주택|상가|요양원|요양병원|병원|학교|마트)")
_LEAD = re.compile(r"^.*?찾습니다[.!]?\s*")
_TAIL = re.compile(r"\s*☎\s*\d+\s*(?:\[[^\]]*\])?\s*$")


def redact(text):
    t = text or ""
    t = _PHONE.sub("[전화번호]", t)
    t = _LONG_NUMBER.sub("[번호]", t)
    t = _UNIT.sub("", t)
    t = _LOT.sub("", t)
    t = _ROAD.sub("", t)
    t = _BUILDING.sub("", t)
    t = _NAME.sub(MASK, t)
    return re.sub(r"\s{2,}", " ", t).strip()


def clothing_part(text):
    t = redact(text)
    t = _LEAD.sub("", t, count=1)
    t = _TAIL.sub("", t)
    return t.strip(" ,")
