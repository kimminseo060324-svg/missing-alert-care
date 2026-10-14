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
    assert m["hallucination"]["count"] == 1
    assert m["negatives"]["correct"] == len(MISSING) - 1
    assert set(wrong) == {sn, sn2}


@pytest.mark.parametrize(("pred", "gold", "ok"), [
    ("블라우스", "꽃무늬 블라우스", True), ("잠옷", "잠옷 상하의", True), ("청바지", "청바지", True),
    ("코트", "점퍼", False), ("", "점퍼", False),
])
def test_type_match(pred, gold, ok):
    assert evaluate.type_match(pred, gold) is ok


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
        "lower": _slot("바지", "남색", "검정바지"),        # 색이 근거와 다름 → 버림
        "shoes": _slot("운동화", "흰색", "흰색운동화"),     # 원문에 없음 → 버림
        "accessories": [_slot("지팡이", "", "지팡이사용"), _slot("모자", "", "")],  # 근거 없음 → 버림
        "negatives": [{"type": "안경", "evidence": "안경미착용"}],                   # 원문에 없음 → 버림
        "summary": [{"text": "지팡이 사용", "evidence": "지팡이사용"}, {"text": "빨간 가방", "evidence": "빨간 가방"}],
    }
    out, dropped = verify_ai_response(resp, TEXT)
    assert out["upper"] == {"type": "점퍼", "color": "회색"}
    assert out["lower"]["type"] == "" and out["shoes"]["type"] == ""
    assert out["accessories"] == [{"type": "지팡이", "color": ""}]
    assert out["negatives"] == [] and out["summary"] == ["지팡이 사용"]
    assert dropped == 5


# Gemini 호출부 (가짜 클라이언트) -----------------------------------------------------

def test_ai_without_key_exits_with_notice(monkeypatch):
    monkeypatch.setattr(extract_ai, "load_dotenv", lambda *a, **k: None)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    with pytest.raises(SystemExit) as e:
        extract_ai.get_client()
    assert "GEMINI_API_KEY" in str(e.value)


class _FakeClient:
    def __init__(self, text=None, error=None):
        self.calls = []
        outer = self

        class Models:
            def generate_content(self, model, contents, config):
                outer.calls.append({"model": model, "contents": contents, "config": config})
                if error:
                    raise error
                return type("R", (), {"text": text})()
        self.models = Models()


def test_ai_extract_sends_redacted_text_with_schema_and_temperature_0():
    resp = {"upper": _slot("점퍼", "회색", "회색점퍼"), "lower": _slot(), "shoes": _slot(),
            "accessories": [], "negatives": [], "summary": []}
    client = _FakeClient(text=json.dumps(resp, ensure_ascii=False))
    out, dropped = extract_ai.extract(client, "양산동에서 실종된 김가상씨(남, 82세)를 찾습니다. 회색점퍼 ☎112[오산시]")
    sent = client.calls[0]
    assert "김가상" not in sent["contents"] and "회색점퍼" in sent["contents"]
    assert sent["config"].temperature == 0 and sent["config"].response_json_schema
    assert out["upper"] == {"type": "점퍼", "color": "회색"} and dropped == 0


def test_ai_error_hides_response_body():
    from google.genai import errors
    err = errors.ClientError(403, {"error": {"code": 403, "message": "BODY-MARKER", "status": "PERMISSION_DENIED"}})
    with pytest.raises(extract_ai.AIError) as e:
        extract_ai.extract(_FakeClient(error=err), "회색점퍼")
    assert "403" in str(e.value) and "BODY-MARKER" not in str(e.value)
    assert e.value.__cause__ is None and e.value.__suppress_context__


def test_ai_non_json_response():
    with pytest.raises(extract_ai.AIError, match="JSON"):
        extract_ai.extract(_FakeClient(text="<html>BODY-MARKER</html>"), "회색점퍼")
