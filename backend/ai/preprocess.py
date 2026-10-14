"""재난문자 개인정보 제거. AI에 보내기 전에 쓴다.

redact(): 이름(○○○씨/군/양, "○○○(남,76)", "○○○(남24)", "○○○ 할머니", "/○○○/남/85/" 등), 식별번호·긴 숫자, 전화번호,
          상세 주소(번지·도로명 번호·호수·건물명)를 지운다.
          동 단위 지역, 신고 번호(☎112·☎182), 나이·키·몸무게는 남긴다.
clothing_part(): redact() 후, "…를 찾습니다." 앞부분과 끝의 신고 번호·발송 기관을 떼고 인상착의 부분만 남긴다.
"""
import re

MASK = "○○○"
_NAME = re.compile(r"[가-힣]{2,4}(?=(?:씨|군|양)(?:\(|\s|을|를|이|가|의|$))")
_TITLES = "어린이|할머니|할아버지|어르신|학생|님"
# 호칭 없이 "최샘플(남,76)", "변가명(남24)"처럼 성별·나이 괄호가 바로 붙은 이름
_NAME_PAREN = re.compile(rf"(?<![가-힣])(?!{_TITLES})[가-힣]{{2,4}}(?=\s?\((?:남|여)\s*[,)\d])")
# "서임시 어린이", "장예문 할머니"처럼 호칭이 붙은 이름
_NAME_TITLE = re.compile(rf"[가-힣]{{2,4}}(?=\s?(?:{_TITLES})(?:\(|\s|을|를|이|가|의|$))")
# "/장예제/남/85/"처럼 슬래시로 나눈 형식의 이름
_NAME_SLASH = re.compile(r"(?<![가-힣])[가-힣]{2,4}(?=\s*/\s*(?:남|여)\s*/)")
_PHONE = re.compile(r"(?<!\d)0\d{1,2}[-.\s]?\d{3,4}[-.\s]?\d{4}(?!\d)")
_LONG_NUMBER = re.compile(r"(?<![\d.])\d{7,}(?![\d.])")  # 식별번호 등 (키·몸무게·나이·신고번호는 7자리 미만)
_LOT = re.compile(r"(?:산\s?)?\d+(?:-\d+)?\s*번지")
# 도로명 주소 "○○로 123", "○○길 45", "○○로123번길 4". 조사 "으로"(남색으로 170cm)는 도로명이 아니고,
# 번호 뒤에 단위가 붙으면(170cm, 2벌, 45세) 주소 번호가 아니다.
_ROAD = re.compile(
    r"[가-힣0-9]+(?<!으)(?:로|길)\s*\d+(?:번길)?(?:-\d+)?(?:\s*번)?"
    r"(?![\d.]|\s*(?:cm|kg|센티|키로|m|벌|개|세|살|명|시|분|켤레|장|원|%))")
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
    for pattern in (_NAME, _NAME_TITLE, _NAME_PAREN, _NAME_SLASH):  # 호칭 규칙을 먼저 (호칭 단어를 이름으로 지우지 않게)
        t = pattern.sub(MASK, t)
    return re.sub(r"\s{2,}", " ", t).strip()


def clothing_part(text):
    t = redact(text)
    t = _LEAD.sub("", t, count=1)
    t = _TAIL.sub("", t)
    return t.strip(" ,")
