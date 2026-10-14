"""키워드·정규식 기반 옷차림 추출 ("규칙 vs AI" 비교용).

정답 파일을 보지 않고, 일반적인 옷 이름·색 표현 목록으로만 찾는다.
- 붙여 쓰기("청색체크남방검정면바지갈색구두")도 왼쪽부터 가장 긴 단어로 끊어 읽는다.
- 색은 옷 이름 바로 앞(띄어쓰기 허용)에 있을 때만 그 옷의 색으로 본다.
- 부정 표현("모자미착용", "안경 미착용", "맨발")은 먼저 찾아 negatives로 빼고, 옷 목록에서는 제외한다.
"""
import re

from .preprocess import clothing_part
from .schema import COLOR_ALIASES, empty_output, normalize_color

ITEMS = {
    "upper": ["롱패딩", "패딩조끼", "누빔조끼", "패딩", "조끼", "점퍼", "잠바", "자켓", "재킷", "코트", "바람막이",
              "후드집업", "후드티", "맨투맨", "티셔츠", "반팔티", "긴팔티", "와이셔츠", "셔츠", "체크남방", "남방",
              "블라우스", "니트", "스웨터", "카디건", "가디건", "등산복상의", "상의",
              # 전신 옷은 upper (정답 매핑과 같은 규칙)
              "잠옷 상하의", "원피스", "작업복", "잠옷", "체육복"],
    "lower": ["트레이닝바지", "등산바지", "정장바지", "몸빼바지", "면바지", "청바지", "반바지", "바지",
              "레깅스", "치마", "스커트", "하의"],
    "shoes": ["운동화", "등산화", "구두", "단화", "슬리퍼", "샌들", "크록스", "장화", "털신", "고무신", "실내화", "신발"],
    "accessories": ["모자", "안경", "백팩", "책가방", "가방", "목도리", "마스크", "지팡이", "보행보조기", "휠체어"],
}
ITEM_SLOT = {item: slot for slot, items in ITEMS.items() for item in items}
MODIFIERS = ["꽃무늬", "줄무늬", "물방울무늬", "땡땡이"]  # 옷 이름 앞에 붙는 무늬
NEGATIONS = r"(?:미착용|미소지|안\s*씀|착용\s*안\s*함|없음)"
MOBILITY = {"지팡이", "보행보조기", "휠체어"}


def _alt(words):
    return "|".join(re.escape(w) for w in sorted(words, key=len, reverse=True))


_ITEM_RE = re.compile(
    rf"(?P<color>{_alt(COLOR_ALIASES)})?\s*(?P<mod>(?:{_alt(MODIFIERS)})\s*)?(?P<item>{_alt(ITEM_SLOT)})")
_NEG_RE = re.compile(rf"(?P<item>{_alt(ITEM_SLOT)})\s*{NEGATIONS}")
_BAREFOOT = re.compile(r"맨발")


def is_missing_message(text):
    """실종 문자인지 (실종 아닌 문자 제외 판단). AI 모드에서도 같은 기준으로 먼저 거른다."""
    return bool(re.search(r"실종|찾습니다|배회", text or ""))


def extract(text):
    """원문 하나 → 출력 형식. 개인정보를 뺀 인상착의 부분만 본다."""
    t = clothing_part(text)
    out = empty_output()
    spans = []  # summary용 원문 조각

    # 1) 부정 표현을 먼저 찾아 빼 둔다
    for m in _NEG_RE.finditer(t):
        item = m.group("item")
        out["negatives"].append("신발" if ITEM_SLOT[item] == "shoes" else item)
    if _BAREFOOT.search(t):
        out["negatives"].append("신발")
    t_pos = _NEG_RE.sub(" ", _BAREFOOT.sub(" ", t))

    # 2) 옷·소지품
    for m in _ITEM_RE.finditer(t_pos):
        item, slot = m.group("item"), ITEM_SLOT[m.group("item")]
        typ = (m.group("mod") or "") + item
        entry = {"type": typ.strip(), "color": normalize_color(m.group("color"))}
        if slot == "accessories":
            if entry["type"] not in [a["type"] for a in out["accessories"]]:
                out["accessories"].append(entry)
        elif not out[slot]["type"]:  # 같은 부위가 여러 번 나오면 처음 것
            out[slot] = entry
        else:
            continue
        spans.append((slot, item, m.group(0).strip()))

    out["summary"] = _summary(spans)
    return out


def _summary(spans):
    """길에서 알아보기 쉬운 특징 3개. 드문 것 우선: 보조기구 > 무늬 > 색 있는 겉옷·신발 > 나머지."""
    def rank(s):
        slot, item, text = s
        if item in MOBILITY:
            return 0
        if any(mod in text for mod in MODIFIERS) or "체크" in text:
            return 1
        has_color = text != item
        return {"upper": 2, "shoes": 3, "accessories": 4, "lower": 5}[slot] + (0 if has_color else 4)
    return [text for _, _, text in sorted(spans, key=rank)[:3]]
