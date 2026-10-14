"""옷차림 추출 출력 형식, 색 표준화, 정답 파일 ↔ 출력 형식 변환, 근거 문구 검증.

출력 형식(고정):
  {"upper": {"type", "color"}, "lower": {...}, "shoes": {...},
   "accessories": [{"type", "color"}], "negatives": ["모자", ...], "summary": ["...", "...", "..."]}

정답 파일(sample-data/disaster-messages-labels.json) → 출력 형식 매핑 규칙:
  상의 → upper, 하의 → lower, 신발 → shoes
  전신(원피스·작업복·잠옷 상하의·체육복) → upper (lower는 비움)
  모자, 착용품(안경·백팩·책가방) → accessories
  특이사항 중 보조기구(지팡이·보행보조기·휠체어) → accessories (길에서 알아보기 쉬운 단서라서)
  착용 안 함(not_wearing) → negatives
  summary는 정답이 없다 (평가에서는 원문 근거가 있는지만 본다)
색은 표준색으로 모은다. 곤색·네이비·남색 → 남색, 청색은 남색과 다른 색으로 둔다.
"""
import re
from difflib import SequenceMatcher

SLOTS = ("upper", "lower", "shoes")
PART_TO_SLOT = {"상의": "upper", "전신": "upper", "하의": "lower", "신발": "shoes"}
ACCESSORY_PARTS = {"모자", "착용품"}
MOBILITY_AIDS = ("지팡이", "보행보조기", "휠체어")  # 정답에서는 features에 있다

# 문자에 적힌 색 표현 → 표준색 (청색은 남색과 별개)
COLOR_ALIASES = {
    "검정": "검정", "검정색": "검정", "검은": "검정", "검은색": "검정", "까만": "검정", "까만색": "검정", "블랙": "검정",
    "흰색": "흰색", "흰": "흰색", "하얀": "흰색", "하얀색": "흰색", "화이트": "흰색",
    "회색": "회색", "그레이": "회색", "쥐색": "회색",
    "남색": "남색", "곤색": "남색", "네이비": "남색",
    "청색": "청색",
    "파란": "파란색", "파란색": "파란색", "파랑": "파란색", "파랑색": "파란색",
    "하늘색": "하늘색",
    "빨간": "빨간색", "빨간색": "빨간색", "빨강": "빨간색", "빨강색": "빨간색",
    "노란": "노란색", "노란색": "노란색", "노랑": "노란색", "노랑색": "노란색",
    "분홍": "분홍색", "분홍색": "분홍색", "핑크": "분홍색",
    "보라": "보라색", "보라색": "보라색",
    "자주": "자주색", "자주색": "자주색",
    "초록": "초록색", "초록색": "초록색", "녹색": "초록색",
    "갈색": "갈색", "밤색": "갈색",
    "베이지": "베이지색", "베이지색": "베이지색",
    "카키": "카키색", "카키색": "카키색",
    "주황": "주황색", "주황색": "주황색",
}
STANDARD_COLORS = sorted(set(COLOR_ALIASES.values()))

# 같은 옷을 가리키는 다른 표현 → 비교용 표준 표현. 채점(evaluate)과 AI 근거 검증에만 쓴다.
# (규칙 추출기 단어 목록에는 넣지 않는다: 평가용 문자에 맞춰 규칙을 고치면 평가가 의미 없어진다)
TYPE_SYNONYMS = {
    "츄리닝": "트레이닝", "추리닝": "트레이닝", "트레이닝복": "트레이닝",
    "쓰레빠": "슬리퍼", "슬리파": "슬리퍼",
    "반소매티셔츠": "반소매티셔츠", "반팔티셔츠": "반소매티셔츠", "반팔티": "반소매티셔츠", "반팔": "반소매",
    "칠부": "7부", "등산복바지": "등산바지",
    "체크무늬": "체크", "남방": "셔츠",
    "가디건": "카디건", "잠바": "점퍼", "스니커즈": "운동화",
    "휴대폰": "휴대폰", "핸드폰": "휴대폰", "휴대전화": "휴대폰", "폰": "휴대폰",
}
_SYN_RE = re.compile("|".join(sorted(map(re.escape, TYPE_SYNONYMS), key=len, reverse=True)))


def canonical_type(text):
    """띄어쓰기를 빼고 다른 표현을 표준 표현으로 바꾼다 (비교용)."""
    return _SYN_RE.sub(lambda m: TYPE_SYNONYMS[m.group(0)], re.sub(r"\s+", "", text or ""))


def normalize_color(text):
    """색 표현을 표준색으로. 모르는 표현이나 빈 값은 ""."""
    t = (text or "").strip()
    return COLOR_ALIASES.get(t, t if t in STANDARD_COLORS else "")


def empty_output():
    return {**{s: {"type": "", "color": ""} for s in SLOTS}, "accessories": [], "negatives": [], "summary": []}


# 최종 출력 JSON Schema
_SLOT = {"type": "object", "properties": {"type": {"type": "string"}, "color": {"type": "string"}},
         "required": ["type", "color"], "additionalProperties": False}
OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        **{s: _SLOT for s in SLOTS},
        "accessories": {"type": "array", "items": _SLOT},
        "negatives": {"type": "array", "items": {"type": "string"}},
        "summary": {"type": "array", "items": {"type": "string"}, "maxItems": 3},
    },
    "required": [*SLOTS, "accessories", "negatives", "summary"],
    "additionalProperties": False,
}

# AI 응답 JSON Schema: 항목마다 원문에서 그대로 옮긴 근거 문구(evidence)를 함께 받는다
_EVIDENCE = {"type": "string", "description": "원문에서 그대로 옮긴 근거 문구. 없으면 빈 문자열"}
_AI_SLOT = {
    "type": "object",
    "properties": {
        "type": {"type": "string", "description": "옷 종류. 원문에 없으면 빈 문자열"},
        "color": {"type": "string", "enum": ["", *STANDARD_COLORS]},
        "evidence": _EVIDENCE,
    },
    "required": ["type", "color", "evidence"],
}
AI_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "is_missing_alert": {"type": "boolean", "description": "실종자를 찾는 문자이면 true"},
        **{s: _AI_SLOT for s in SLOTS},
        "accessories": {"type": "array", "items": _AI_SLOT},
        "negatives": {"type": "array", "items": {"type": "object", "properties": {
            "type": {"type": "string"}, "evidence": _EVIDENCE}, "required": ["type", "evidence"]}},
        "summary": {"type": "array", "maxItems": 3, "items": {"type": "object", "properties": {
            "text": {"type": "string"}, "evidence": _EVIDENCE}, "required": ["text", "evidence"]}},
    },
    "required": ["is_missing_alert", *SLOTS, "accessories", "negatives", "summary"],
}


def label_to_output(label):
    """정답 파일 항목 하나 → 출력 형식 (summary는 비움)."""
    out = empty_output()
    for c in label.get("clothing") or []:
        item = {"type": c["item"], "color": c["color"] or ""}
        slot = PART_TO_SLOT.get(c["part"])
        if slot:
            if not out[slot]["type"]:  # 같은 부위가 둘이면 처음 것
                out[slot] = item
        elif c["part"] in ACCESSORY_PARTS:
            out["accessories"].append(item)
    for f in label.get("features") or []:
        aid = next((a for a in MOBILITY_AIDS if a in f), None)
        if aid:
            out["accessories"].append({"type": aid, "color": ""})
    out["negatives"] = list(label.get("not_wearing") or [])
    return out


def _squash(s):
    return re.sub(r"\s+", "", s or "")


def grounded(evidence, text):
    """근거 문구가 원문에 실제로 있는지 (띄어쓰기는 무시)."""
    e = _squash(evidence)
    return bool(e) and e in _squash(text)


# 색 표준표에는 없지만 문자에 쓰일 수 있는 색 표현 (AI 근거 검증에서 "근거에 색이 적혀 있다"고 볼 때만 쓴다)
OTHER_COLOR_WORDS = ("아이보리", "와인", "버건디", "민트", "올리브", "크림", "차콜", "오트밀", "머스타드", "라벤더", "코랄", "브라운")


def type_in_evidence(typ, evidence):
    """옷 종류가 근거 문구에서 나온 것인지. 다른 표현(츄리닝→트레이닝)과 오타 한 글자 정도는 허용:
    표준 표현으로 바꾼 뒤 가장 긴 공통 부분이 종류 길이의 절반 이상(최소 2글자)이어야 한다."""
    t, e = canonical_type(typ), canonical_type(evidence)
    if not t:
        return False
    m = SequenceMatcher(None, t, e).find_longest_match(0, len(t), 0, len(e))
    if m.size >= max(2, -(-len(t) // 2)):
        return True
    # 두 글자 단어의 한 글자 오타 (잠퍼 → 점퍼): 근거 안에 같은 길이에 한 글자만 다른 부분이 있으면 인정
    return len(t) >= 2 and any(
        sum(a != b for a, b in zip(t, e[i:i + len(t)])) == 1 for i in range(len(e) - len(t) + 1))


def color_in_evidence(color, evidence):
    """색을 지어내지 않았는지. 색이 없으면 통과. 있으면 근거에 그 색 표현, 또는 표준표에 없는 색 표현
    ("~색", 아이보리·와인 등)이 있어야 한다."""
    if not color:
        return True
    ev = _squash(evidence)
    if any(alias in ev for alias, std in COLOR_ALIASES.items() if std == color):
        return True
    known = [a for a in COLOR_ALIASES if a in ev]
    return not known and (bool(re.search(r"[가-힣]+색", ev)) or any(w in ev for w in OTHER_COLOR_WORDS))


def verify_ai_response(resp, text):
    """AI 응답(근거 포함)을 원문으로 검증해 출력 형식으로 바꾼다.

    근거가 원문에 없거나, 종류·색이 근거 안에 보이지 않으면 그 항목을 버린다 (환각 방지).
    (출력, 버린 항목 수)를 돌려준다.
    """
    out, dropped = empty_output(), 0

    def slot_ok(s):
        ev = s.get("evidence", "")
        if not s.get("type") or not grounded(ev, text) or not type_in_evidence(s["type"], ev):
            return False
        return color_in_evidence(normalize_color(s.get("color")), ev)

    for slot in SLOTS:
        s = resp.get(slot) or {}
        if s.get("type"):
            if slot_ok(s):
                out[slot] = {"type": s["type"].strip(), "color": normalize_color(s.get("color"))}
            else:
                dropped += 1
    for a in resp.get("accessories") or []:
        if slot_ok(a):
            out["accessories"].append({"type": a["type"].strip(), "color": normalize_color(a.get("color"))})
        else:
            dropped += 1
    for n in resp.get("negatives") or []:
        if n.get("type") and grounded(n.get("evidence"), text):
            out["negatives"].append(n["type"].strip())
        else:
            dropped += 1
    for s in (resp.get("summary") or [])[:3]:
        if s.get("text") and grounded(s.get("evidence"), text):
            out["summary"].append(s["text"].strip())
        else:
            dropped += 1
    return out, dropped
