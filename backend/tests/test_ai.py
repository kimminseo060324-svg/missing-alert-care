"""AI 옷차림 추출 준비 코드 테스트. Gemini는 부르지 않는다 (가짜 클라이언트 사용)."""
import copy
import json
from pathlib import Path

import pytest

from ai import evaluate, extract_ai, extract_rule, preprocess
from ai.schema import label_to_output, verify_ai_response

DATA = Path(__file__).resolve().parents[2] / "sample-data"
MSGS = {m["SN"]: m["MSG_CN"] for m in json.loads((DATA / "disaster-messages.json").read_text(encoding="utf-8"))["body"]}
LABELS = {l["SN"]: l for l in json.loads((DATA / "disaster-messages-labels.json").read_text(encoding="utf-8"))["labels"]}
MISSING = [sn for sn, l in LABELS.items() if l["is_missing"]]
GOLDS = {sn: label_to_output(LABELS[sn]) for sn in MISSING}


# 평가 ---------------------------------------------------------------------

def test_gold_scores_100_percent():
    ok, metrics = evaluate.self_test(GOLDS)
    assert ok and metrics["all_fields"]["accuracy"] == 1.0


def test_evaluator_catches_errors():
    pred = copy.deepcopy(GOLDS)
    sn = next(s for s in pred if not pred[s]["shoes"]["type"])
    pred[sn]["shoes"] = {"type": "운동화", "color": "흰색"}  # 없는 신발을 지어냄
    sn2 = next(s for s in pred if pred[s]["negatives"])
    pred[sn2]["negatives"] = []
    m, wrong = evaluate.evaluate(pred, GOLDS)
    assert m["hallucination"]["count"] == 2  # 지어낸 신발 종류 1 + 정답에 없는 색 1
    assert m["negatives"]["correct"] == len(MISSING) - 1
    assert set(wrong) == {sn, sn2}


@pytest.mark.parametrize(("pred", "gold", "ok"), [
    ("블라우스", "꽃무늬 블라우스", True), ("잠옷", "잠옷 상하의", True), ("청바지", "청바지", True),
    ("코트", "점퍼", False), ("", "점퍼", False),
    # 같은 옷의 다른 표현
    ("츄리닝바지", "트레이닝 바지", True), ("쓰레빠", "슬리퍼", True), ("반팔티", "반소매 티셔츠", True),
    ("체크남방", "체크무늬 셔츠", True), ("폰", "휴대폰", True), ("가디건", "카디건", True),
    # 오타를 그대로 옮긴 것은 맞다고 보지 않는다
    ("잠퍼", "점퍼", False),
])
def test_type_match(pred, gold, ok):
    assert evaluate.type_match(pred, gold) is ok


def test_color_without_gold_color_is_not_scored_but_invented_color_is_hallucination():
    gold = {"upper": {"type": "", "color": ""}, "lower": {"type": "", "color": ""},
            "shoes": {"type": "슬리퍼", "color": ""}, "accessories": [], "negatives": [], "summary": []}
    pred = copy.deepcopy(gold)
    pred["shoes"]["color"] = "검정"  # 문자에 색이 없는데 색을 붙임
    m, _ = evaluate.evaluate({1: pred}, {1: gold})
    assert m["color"]["total"] == 0  # 색 채점에서 빠짐
    assert m["hallucination"]["count"] == 1  # 대신 환각으로 셈


# 개인정보 제거 ----------------------------------------------------------------

@pytest.mark.parametrize("sn", MISSING)
def test_preprocess_removes_name_and_keeps_clothing(sn):
    label, text = LABELS[sn], preprocess.clothing_part(MSGS[sn])
    assert label["name"] not in preprocess.redact(MSGS[sn]) and label["name"] not in text
    for c in label["clothing"]:
        assert c["item"] in text and (not c["color_text"] or c["color_text"] in text)


def test_redact_removes_phone_id_and_detailed_address():
    raw = "마포구 망원동 123-45번지 가상아파트 101동 1203호에서 실종된 김가상씨(남, 82세) 010-1234-5678 1234567 ☎112"
    out = preprocess.redact(raw)
    for secret in ["123-45번지", "가상아파트", "1203호", "김가상", "010-1234-5678", "1234567"]:
        assert secret not in out
    assert "망원동" in out and "☎112" in out and "82세" in out


# 규칙 추출 ---------------------------------------------------------------------

def test_rule_excludes_non_missing_messages():
    assert all(extract_rule.is_missing_message(MSGS[sn]) == LABELS[sn]["is_missing"] for sn in LABELS)


def test_rule_handles_run_together_and_negation():
    out = extract_rule.extract("○○○씨를 찾습니다. 청색체크남방검정면바지갈색구두, 안경미착용, 맨발 ☎112")
    assert out["upper"] == {"type": "체크남방", "color": "청색"}
    assert out["lower"] == {"type": "면바지", "color": "검정"}
    assert out["shoes"] == {"type": "구두", "color": "갈색"}
    assert out["accessories"] == [] and sorted(out["negatives"]) == ["신발", "안경"]


# AI 응답 검증 (환각 방지) ----------------------------------------------------------

TEXT = "흰머리, 회색점퍼, 검정바지, 지팡이사용"


def _slot(t="", c="", ev=""):
    return {"type": t, "color": c, "evidence": ev}


def test_verify_drops_items_without_evidence():
    resp = {
        "upper": _slot("점퍼", "회색", "회색점퍼"),
        "lower": _slot("바지", "남색", "검정바지"),        # 색만 근거와 다름 → 색만 비우고 종류는 남김
        "shoes": _slot("운동화", "흰색", "흰색운동화"),     # 원문에 없음 → 버림
        "accessories": [_slot("지팡이", "", "지팡이사용"), _slot("모자", "", "")],  # 근거 없음 → 버림
        "negatives": [{"type": "안경", "evidence": "안경미착용"}],                   # 원문에 없음 → 버림
        "summary": [{"text": "지팡이 사용", "evidence": "지팡이사용"}, {"text": "빨간 가방", "evidence": "빨간 가방"}],
    }
    out, dropped = verify_ai_response(resp, TEXT)
    assert out["upper"] == {"type": "점퍼", "color": "회색"}
    assert out["lower"] == {"type": "바지", "color": ""} and out["shoes"]["type"] == ""
    assert out["accessories"] == [{"type": "지팡이", "color": ""}]
    assert out["negatives"] == [] and out["summary"] == ["지팡이 사용"]
    assert dropped == 5  # 비운 색 1 + 버린 항목 4

    old, _ = verify_ai_response(resp, TEXT, lenient=False)  # 예전 방식은 색이 틀리면 항목 전체를 버림
    assert old["lower"]["type"] == ""


@pytest.mark.parametrize(("slot", "evidence", "expected"), [
    (_slot("트레이닝 바지", "검정", "검정 츄리닝바지"), "검정 츄리닝바지", ("트레이닝 바지", "검정")),  # 줄임말을 표준 표현으로
    (_slot("점퍼", "남색", "남색잠퍼"), "남색잠퍼", ("점퍼", "남색")),                    # 오타를 바로잡음
    (_slot("니트", "흰색", "아이보리 니트"), "아이보리 니트", ("니트", "흰색")),          # 표준표 밖 색 표현
    (_slot("슬리퍼", "검정", "슬리퍼 차림"), "슬리퍼 차림", ("슬리퍼", "")),              # 색을 지어냄 → 색만 비움
    (_slot("청바지", "청색", "7부청바지"), "7부청바지", ("청바지", "")),                  # 청바지의 '청'은 색이 아님
    (_slot("코트", "검정", "검정 롱패딩"), "검정 롱패딩", None),                          # 다른 옷 → 버림
    (_slot("가방", "갈색", "갈색 숄더백"), "갈색 숄더백", ("가방", "갈색")),              # 상위 개념으로 일반화 → 인정
    (_slot("바지", "남색", "곤색하의"), "곤색하의", ("바지", "남색")),                    # 하의 → 바지 → 인정
    (_slot("운동화", "흰색", "흰신발"), "흰신발", None),                                  # 지어낸 구체 정보 → 버림
])
def test_verify_allows_synonyms_typos_and_generalization_but_not_invention(slot, evidence, expected):
    resp = {"upper": slot, "lower": _slot(), "shoes": _slot(), "accessories": [], "negatives": [], "summary": []}
    out, _ = verify_ai_response(resp, evidence)
    got = (out["upper"]["type"], out["upper"]["color"]) if out["upper"]["type"] else None
    assert got == expected


TEXT2 = "회색점퍼, 검정바지, 지팡이사용"
GOOD_ACC = {"type": "지팡이", "color": None, "evidence": "지팡이사용"}


@pytest.mark.parametrize(("resp", "invalid"), [
    ([], 1),                                                                  # 응답이 객체가 아님
    ("문자열", 1),
    ({"upper": "회색 점퍼"}, 1),                                              # 칸이 객체가 아님
    ({"upper": {"type": 123, "color": "회색", "evidence": "회색점퍼"}}, 1),   # type이 문자열이 아님
    ({"lower": {"type": "바지", "color": ["검정"], "evidence": "검정바지"}}, 1),
    ({"shoes": {"type": "운동화", "color": None, "evidence": {"x": 1}}}, 1),  # evidence가 객체
    ({"accessories": "지팡이"}, 1),                                           # 목록이 아님
    ({"accessories": ["지팡이", GOOD_ACC]}, 1),                               # 목록 원소가 객체가 아님 (정상 원소는 남음)
    ({"negatives": [1, {"type": "모자", "evidence": 5}]}, 2),
    ({"summary": {"text": "x"}}, 1),
    ({"summary": [None, {"text": True, "evidence": "x"}]}, 2),
    ({"upper": None, "accessories": None, "negatives": None, "summary": None}, 0),  # null은 빈 값으로 봄
])
def test_malformed_ai_response_is_skipped_without_error(resp, invalid):
    stats = {}
    out, _ = verify_ai_response(resp, TEXT2, stats=stats)
    assert stats["invalid"] == invalid
    assert set(out) == {"upper", "lower", "shoes", "accessories", "negatives", "summary"}
    if resp == {"accessories": ["지팡이", GOOD_ACC]}:
        assert out["accessories"] == [{"type": "지팡이", "color": ""}]


def test_malformed_is_missing_alert_is_treated_as_false():
    out, _, is_missing = extract_ai.verify({"is_missing_alert": "true", "upper": None}, "회색점퍼")
    assert is_missing is False
    assert extract_ai.verify(["not", "dict"], "회색점퍼")[2] is False


def test_strict_verify_does_not_accept_generalization():
    resp = {"upper": _slot(), "lower": _slot(), "shoes": _slot(), "negatives": [], "summary": [],
            "accessories": [_slot("가방", "갈색", "갈색 숄더백")]}
    assert verify_ai_response(resp, "갈색 숄더백")[0]["accessories"] == [{"type": "가방", "color": "갈색"}]
    assert verify_ai_response(resp, "갈색 숄더백", lenient=False)[0]["accessories"] == []


def test_summary_counts_only_clothing_and_belongings():
    gold = {"upper": {"type": "점퍼", "color": "남색"}, "lower": {"type": "", "color": ""},
            "shoes": {"type": "운동화", "color": "검정"}, "accessories": [{"type": "우산", "color": "빨간색"}],
            "negatives": [], "summary": []}
    pred = copy.deepcopy(gold)
    pred["summary"] = ["빨간 우산", "남색잠퍼", "82세 남성"]  # 나이·성별은 옷·소지품이 아님
    m, _ = evaluate.evaluate({1: pred}, {1: gold})
    assert (m["summary_on_items"]["count"], m["summary_on_items"]["total"]) == (2, 3)


# 평가용 데이터 (disaster-messages-eval) -----------------------------------------------

EVAL_MSGS = {m["SN"]: m["MSG_CN"] for m in json.loads((DATA / "disaster-messages-eval.json").read_text(encoding="utf-8"))["body"]}
EVAL_LABELS = {l["SN"]: l for l in json.loads((DATA / "disaster-messages-eval-labels.json").read_text(encoding="utf-8"))["labels"]}


def test_eval_files_match_sample_structure():
    sample_msg = json.loads((DATA / "disaster-messages.json").read_text(encoding="utf-8"))
    eval_msg = json.loads((DATA / "disaster-messages-eval.json").read_text(encoding="utf-8"))
    assert list(eval_msg) == list(sample_msg)
    assert all(list(m) == list(sample_msg["body"][0]) for m in eval_msg["body"])
    assert sorted(EVAL_MSGS) == sorted(EVAL_LABELS) == list(range(9910001, 9910031))
    assert not set(EVAL_MSGS) & set(MSGS)
    assert all(set(l) == set(next(iter(LABELS.values()))) and l["is_missing"] for l in EVAL_LABELS.values())


def test_eval_gold_scores_100_percent():
    ok, _ = evaluate.self_test({sn: label_to_output(l) for sn, l in EVAL_LABELS.items()})
    assert ok


def test_eval_labels_use_standard_colors():
    from ai.schema import STANDARD_COLORS
    colors = {c["color"] for l in EVAL_LABELS.values() for c in l["clothing"]}
    assert colors - {None} <= set(STANDARD_COLORS)


@pytest.mark.parametrize("sn", sorted(EVAL_LABELS))
def test_eval_preprocess_removes_names(sn):
    # "최샘플(남,76)", "서임시 어린이", "장예문 할머니"처럼 '씨'가 없는 이름도 지운다
    assert EVAL_LABELS[sn]["name"] not in preprocess.redact(EVAL_MSGS[sn])
    assert EVAL_LABELS[sn]["name"] not in preprocess.clothing_part(EVAL_MSGS[sn])


def test_redact_keeps_title_words():
    assert "어린이(남,9세)" in preprocess.redact("고잔동 놀이터에서 서임시 어린이(남,9세) 실종")


@pytest.mark.parametrize("text", ["남색으로 170cm, 회색바지", "흰색으로 2벌 챙김", "흰바지로 2벌", "검정으로 45세"])
def test_redact_keeps_non_address_phrases(text):
    assert preprocess.redact(text) == text  # "○○으로 숫자"와 단위가 붙은 숫자는 주소가 아님


@pytest.mark.parametrize(("text", "removed"), [
    ("세종대로 110 앞", "세종대로 110"), ("한신대길 137 정문", "한신대길 137"),
    ("테헤란로 152-1 근처", "테헤란로 152-1"), ("중앙로123번길 4 앞", "중앙로123번길"),
])
def test_redact_still_removes_road_addresses(text, removed):
    out = preprocess.redact(text)
    assert removed not in out and not any(ch.isdigit() for ch in out)


@pytest.mark.parametrize(("pred", "gold", "loose", "strict"), [
    ("점퍼", "점퍼", True, True), ("트레이닝 바지", "트레이닝바지", True, True),   # 띄어쓰기는 둘 다 무시
    ("츄리닝바지", "트레이닝 바지", True, False),                                   # 동의어
    ("블라우스", "꽃무늬 블라우스", True, False),                                   # 포함 관계
    ("반팔티", "반소매 티셔츠", True, False), ("코트", "점퍼", False, False),
])
def test_strict_scoring_accepts_exact_match_only(pred, gold, loose, strict):
    assert evaluate.type_match(pred, gold) is loose
    assert evaluate.type_match(pred, gold, strict=True) is strict


def test_strict_scoring_lowers_accuracy_for_synonyms():
    gold = {"upper": {"type": "반소매 티셔츠", "color": ""}, "lower": {"type": "트레이닝 바지", "color": ""},
            "shoes": {"type": "슬리퍼", "color": ""}, "accessories": [], "negatives": [], "summary": []}
    pred = copy.deepcopy(gold)
    pred["upper"]["type"], pred["lower"]["type"], pred["shoes"]["type"] = "반팔티", "츄리닝바지", "쓰레빠"
    loose, _ = evaluate.evaluate({1: pred}, {1: gold})
    strict, _ = evaluate.evaluate({1: pred}, {1: gold}, strict=True)
    assert loose["type"]["correct"] == 3 and strict["type"]["correct"] == 0
    assert strict["hallucination"]["count"] == 3


@pytest.mark.parametrize(("raw", "name", "kept"), [
    ("첨단동 변가명(남24) 지적장애 있음", "변가명", "(남24)"),          # 괄호 안 쉼표 없음
    ("[대전시]둔산동/장예제/남/85/162cm", "장예제", "둔산동/"),         # 슬래시 형식
    ("하교 후 사라진 김연습(남,9세) 학생 찾습니다", "김연습", "학생"),
    ("중학생 임가명군(15) 가출 후", "임가명", "군(15)"),
    ("연락두절된 정가짜(남,81) 님을 찾습니다", "정가짜", "님을"),
    ("거동이 불편하신 배샘플(남, 88세) 어르신을", "배샘플", "어르신"),
    ("불당동 조예시 할머니 80세", "조예시", "할머니"),
    ("효자동 이테스트씨 남72세 실종", "이테스트", "남72세"),
])
def test_redact_name_formats(raw, name, kept):
    out = preprocess.redact(raw)
    assert name not in out and kept in out  # 이름만 지우고 호칭·성별·나이는 남긴다


def test_eval_new_labels_follow_rules():
    out = {sn: label_to_output(l) for sn, l in EVAL_LABELS.items()}
    assert out[9910022]["negatives"] == ["모자", "가방"]               # 모자X 가방X
    assert out[9910030]["upper"]["type"] == "꽃무늬 원피스"            # 원피스는 upper
    assert out[9910030]["lower"]["type"] == "스타킹"                   # lower는 스타킹만
    assert out[9910028]["accessories"] == [{"type": "보행보조기", "color": ""}]
    assert {a["type"] for a in out[9910026]["accessories"]} == {"모자", "마스크"}  # 착용한 모자·마스크는 소지품
    assert out[9910008]["upper"]["color"] == "베이지색"                # 아이보리 → 베이지
    assert "일체형" in EVAL_LABELS[9910030]["hard_cases"]


def test_run_eval_datasets():
    from ai import run_eval
    for name, n in [("sample", 45), ("eval", 30), ("all", 75)]:
        msgs, labels = run_eval.load(name)
        assert len(msgs) == len(labels) == n


# Gemini 호출부 (가짜 클라이언트) -----------------------------------------------------

def test_ai_without_key_exits_with_notice(monkeypatch):
    monkeypatch.setattr(extract_ai, "load_dotenv", lambda *a, **k: None)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    with pytest.raises(SystemExit) as e:
        extract_ai.get_client()
    assert "GEMINI_API_KEY" in str(e.value)


class _FakeClient:
    """errors 목록을 차례로 던지고, 다 던진 뒤에는 text를 돌려준다."""

    def __init__(self, text=None, errors=()):
        self.calls = []
        pending = list(errors)
        outer = self

        class Models:
            def generate_content(self, model, contents, config):
                outer.calls.append({"model": model, "contents": contents, "config": config})
                if pending:
                    raise pending.pop(0)
                return type("R", (), {"text": text})()
        self.models = Models()


def _resp(**slots):
    return json.dumps({"is_missing_alert": True, "upper": _slot(), "lower": _slot(), "shoes": _slot(),
                       "accessories": [], "negatives": [], "summary": [], **slots}, ensure_ascii=False)


def _api_error(code):
    from google.genai import errors
    return errors.ClientError(code, {"error": {"code": code, "message": "BODY-MARKER", "status": "X"}})


def test_ai_extract_sends_redacted_text_with_schema_and_temperature_0():
    client = _FakeClient(text=_resp(upper=_slot("점퍼", "회색", "회색점퍼")))
    out, dropped, is_missing = extract_ai.extract(client, "양산동에서 실종된 김가상씨(남, 82세)를 찾습니다. 회색점퍼 ☎112[오산시]")
    sent = client.calls[0]
    assert "김가상" not in sent["contents"] and "회색점퍼" in sent["contents"]
    assert "찾습니다" in sent["contents"]  # 실종 판단을 위해 앞부분도 보낸다 (이름만 지움)
    assert sent["config"].temperature == 0 and sent["config"].response_json_schema
    assert out["upper"] == {"type": "점퍼", "color": "회색"} and dropped == 0 and is_missing is True


def test_ai_error_hides_response_body():
    with pytest.raises(extract_ai.AIError) as e:
        extract_ai.extract(_FakeClient(errors=[_api_error(403)]), "회색점퍼", sleep=lambda s: None)
    assert "403" in str(e.value) and "BODY-MARKER" not in str(e.value)
    assert e.value.__cause__ is None and e.value.__suppress_context__


def test_ai_non_json_response():
    with pytest.raises(extract_ai.AIError, match="JSON"):
        extract_ai.extract(_FakeClient(text="<html>BODY-MARKER</html>"), "회색점퍼")


# 429 재시도 ---------------------------------------------------------------------

def test_429_waits_and_retries_then_succeeds():
    slept, logs = [], []
    client = _FakeClient(text=_resp(), errors=[_api_error(429), _api_error(429)])
    out, _, _ = extract_ai.extract(client, "회색점퍼", sleep=slept.append, log=logs.append)
    assert slept == [15, 30] and len(client.calls) == 3
    assert logs == ["429, 15초 후 재시도 (1/3)", "429, 30초 후 재시도 (2/3)"]
    assert not any("BODY-MARKER" in m for m in logs)


def test_429_gives_up_after_three_retries():
    slept = []
    client = _FakeClient(text=_resp(), errors=[_api_error(429)] * 4)
    with pytest.raises(extract_ai.AIError) as e:
        extract_ai.extract(client, "회색점퍼", sleep=slept.append, log=lambda m: None)
    assert slept == [15, 30, 60] and len(client.calls) == 4
    assert "429" in str(e.value) and "BODY-MARKER" not in str(e.value)


@pytest.mark.parametrize("code", [400, 401, 403, 404])
def test_other_errors_are_not_retried(code):
    slept = []
    with pytest.raises(extract_ai.AIError) as e:
        extract_ai.extract(_FakeClient(errors=[_api_error(code)]), "회색점퍼", sleep=slept.append)
    assert slept == [] and f"HTTP {code})" in str(e.value)


@pytest.mark.parametrize("code", [500, 503])
def test_server_errors_are_retried(code):
    slept, logs = [], []
    client = _FakeClient(text=_resp(), errors=[_api_error(code)])
    extract_ai.extract(client, "회색점퍼", sleep=slept.append, log=logs.append)
    assert slept == [15] and logs == [f"{code}, 15초 후 재시도 (1/3)"] and len(client.calls) == 2


def test_timeout_is_retried_then_gives_up_without_secrets():
    import httpx
    slept, logs = [], []
    err = httpx.ReadTimeout("timed out: https://example/?key=SECRET-KEY body=BODY-MARKER")
    client = _FakeClient(text=_resp(), errors=[err] * 4)
    with pytest.raises(extract_ai.AIError) as e:
        extract_ai.extract(client, "김가상씨(남, 82세) 회색점퍼", sleep=slept.append, log=logs.append)
    assert slept == [15, 30, 60] and len(client.calls) == 4
    msg = str(e.value) + " ".join(logs)
    assert "응답 시간 초과" in msg and "3번 재시도 후" in str(e.value)
    assert "SECRET-KEY" not in msg and "BODY-MARKER" not in msg and "김가상" not in msg
    assert e.value.__cause__ is None and e.value.__suppress_context__


def test_timeout_then_success():
    import httpx
    slept = []
    client = _FakeClient(text=_resp(upper=_slot("점퍼", "회색", "회색점퍼")), errors=[httpx.ConnectTimeout("x")])
    out, _, _ = extract_ai.extract(client, "회색점퍼", sleep=slept.append, log=lambda m: None)
    assert slept == [15] and out["upper"]["type"] == "점퍼"


@pytest.mark.parametrize(("value", "expected_ms"), [
    (None, 30000), ("", 30000), ("abc", 30000), ("0", 30000), ("-5", 30000), ("9999", 30000),
    ("10", 10000), ("2.5", 2500), ("600", 600000),
])
def test_client_timeout_is_set_in_milliseconds(monkeypatch, value, expected_ms):
    import google.genai as genai
    captured = {}
    monkeypatch.setattr(extract_ai, "load_dotenv", lambda *a, **k: None)
    monkeypatch.setenv("GEMINI_API_KEY", "fake-key")
    if value is None:
        monkeypatch.delenv("GEMINI_TIMEOUT_SEC", raising=False)
    else:
        monkeypatch.setenv("GEMINI_TIMEOUT_SEC", value)
    monkeypatch.setattr(genai, "Client", lambda **kw: captured.update(kw) or "client")
    assert extract_ai.get_client() == "client"
    assert captured["http_options"].timeout == expected_ms  # SDK HttpOptions.timeout은 밀리초 정수
    assert captured["http_options"].retry_options is None  # SDK 자체 재시도는 끔 (재시도는 우리 코드에서만)


@pytest.mark.parametrize(("value", "expected"), [
    (None, 4.0), ("", 4.0), ("abc", 4.0), ("-1", 4.0), ("0", 0.0), ("2.5", 2.5), ("10", 10.0), ("9999", 4.0),
])
def test_call_interval(monkeypatch, value, expected):
    if value is None:
        monkeypatch.delenv("GEMINI_CALL_INTERVAL_SEC", raising=False)
    else:
        monkeypatch.setenv("GEMINI_CALL_INTERVAL_SEC", value)
    assert extract_ai.call_interval() == expected


# 중간 저장·이어하기 --------------------------------------------------------------------

def test_run_ai_saves_progress_and_resumes(monkeypatch, tmp_path):
    from ai import run_eval
    monkeypatch.setattr(evaluate, "RESULTS_DIR", tmp_path)
    monkeypatch.setattr(extract_ai, "get_client", lambda: object())
    monkeypatch.setattr(extract_ai, "call_interval", lambda: 0)
    labels = {sn: EVAL_LABELS[sn] for sn in sorted(EVAL_LABELS)[:4]}
    called, fail_on = [], {sorted(labels)[2]}

    def fake_call(client, text, log=print):
        sn = next(s for s in labels if EVAL_MSGS[s] == text)
        called.append(sn)
        if sn in fail_on:
            raise extract_ai.AIError("Gemini API 오류 (HTTP 429, 3번 재시도 후)")
        return {"is_missing_alert": True, "fake_sn": sn}  # AI 원래 응답 자리
    verified = []

    def fake_verify(raw, text, lenient=True, stats=None):
        verified.append(lenient)
        return label_to_output(labels[raw["fake_sn"]]), 0, raw["is_missing_alert"]
    monkeypatch.setattr(extract_ai, "call", fake_call)
    monkeypatch.setattr(extract_ai, "verify", fake_verify)

    with pytest.raises(SystemExit) as e:  # 세 번째에서 멈춤
        run_eval.run_ai(EVAL_MSGS, labels)
    assert "다시 실행하면 이어서" in str(e.value)
    cache = json.loads(next(tmp_path.glob("ai-cache-*.json")).read_text(encoding="utf-8"))
    assert len(cache) == 2 and all("raw" in v for v in cache.values())  # 검증 전 원래 응답을 저장

    fail_on.clear()
    called.clear()
    preds, judged = run_eval.run_ai(EVAL_MSGS, labels)  # 다시 실행: 받은 2건은 건너뜀
    assert called == sorted(labels)[2:]
    assert len(preds) == 4 and all(judged.values())

    called.clear()
    verified.clear()
    run_eval.run_ai(EVAL_MSGS, labels, lenient=False)  # 검증 방식만 바꿔 다시 채점: 다시 부르지 않음
    assert called == [] and verified == [False] * 4

    run_eval.run_ai(EVAL_MSGS, labels, fresh=True)  # --fresh 는 처음부터
    assert called == sorted(labels)
