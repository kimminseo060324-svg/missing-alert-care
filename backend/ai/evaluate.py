"""추출 결과(규칙 또는 AI)를 정답과 필드별로 비교해 정확도를 계산한다.

비교 기준
- 옷 종류: 띄어쓰기를 무시하고 같거나, 한쪽이 다른 쪽을 포함하면 정답 (예: 블라우스 ⊂ 꽃무늬 블라우스).
  upper·lower·shoes 3칸 × 문자 수. 둘 다 비어 있으면 정답.
- 색상: 정답에 옷이 있는 칸만. 표준색이 같으면 정답 (정답 색이 없으면 빈 값이어야 정답).
- 소지품·부정 표현: 문자마다 항목 묶음이 정답과 같으면 정답.
- 전체 필드: 문자 하나의 옷 3칸(종류·색), 소지품, 부정 표현이 모두 맞으면 정답.
- 환각: 결과에 넣은 항목(옷 칸·소지품·부정 표현) 중 정답에 없는 항목의 비율. 낮을수록 좋다.
- 요약 근거 없음: summary 중 원문에 없는 문구의 비율 (summary는 정답이 없어 근거만 본다).
"""
import json
import re
from datetime import datetime
from pathlib import Path

from .schema import SLOTS, grounded, normalize_color

RESULTS_DIR = Path(__file__).resolve().parents[2] / "results"


def _squash(s):
    return re.sub(r"\s+", "", s or "")


def type_match(pred, gold):
    p, g = _squash(pred), _squash(gold)
    if p == g:
        return True
    return bool(p and g) and min(len(p), len(g)) >= 2 and (p in g or g in p)


def _match_list(pred, gold, key=lambda x: x):
    """두 목록을 type_match로 짝지어 (맞은 쌍, 남은 예측, 남은 정답)을 돌려준다."""
    rest_gold = list(gold)
    pairs, extra = [], []
    for p in pred:
        g = next((g for g in rest_gold if type_match(key(p), key(g))), None)
        if g is None:
            extra.append(p)
        else:
            rest_gold.remove(g)
            pairs.append((p, g))
    return pairs, extra, rest_gold


def compare(pred, gold, text=""):
    """문자 하나 비교. 필드별 맞음 여부와 환각 수를 돌려준다."""
    r = {"slots": {}, "hallucinated": 0, "predicted": 0, "summary_total": 0, "summary_ungrounded": 0}
    for s in SLOTS:
        p, g = pred[s], gold[s]
        t_ok = (not p["type"] and not g["type"]) or (bool(p["type"]) and bool(g["type"]) and type_match(p["type"], g["type"]))
        c_ok = normalize_color(p["color"]) == normalize_color(g["color"]) if g["type"] else None
        r["slots"][s] = {"type": t_ok, "color": c_ok}
        if p["type"]:
            r["predicted"] += 1
            r["hallucinated"] += not g["type"] or not type_match(p["type"], g["type"])

    pairs, extra, missing = _match_list(pred["accessories"], gold["accessories"], key=lambda x: x["type"])
    r["accessories"] = not extra and not missing and all(
        normalize_color(p["color"]) == normalize_color(g["color"]) for p, g in pairs)
    r["predicted"] += len(pred["accessories"])
    r["hallucinated"] += len(extra)

    _, extra_n, missing_n = _match_list(pred["negatives"], gold["negatives"])
    r["negatives"] = not extra_n and not missing_n
    r["predicted"] += len(pred["negatives"])
    r["hallucinated"] += len(extra_n)

    r["all"] = all(v["type"] and v["color"] is not False for v in r["slots"].values()) and r["accessories"] and r["negatives"]
    r["summary_total"] = len(pred.get("summary") or [])
    r["summary_ungrounded"] = sum(not grounded(s, text) for s in pred.get("summary") or [])
    return r


def evaluate(preds, golds, texts=None):
    """preds, golds: {SN: 출력 형식}. texts: {SN: 원문} (요약 근거 검사용)."""
    texts = texts or {}
    per = {sn: compare(preds[sn], golds[sn], texts.get(sn, "")) for sn in golds}
    rows = list(per.values())

    def rate(ok, total):
        return {"correct": ok, "total": total, "accuracy": round(ok / total, 4) if total else None}

    slot_types = [v["type"] for r in rows for v in r["slots"].values()]
    slot_colors = [v["color"] for r in rows for v in r["slots"].values() if v["color"] is not None]
    predicted = sum(r["predicted"] for r in rows)
    halluc = sum(r["hallucinated"] for r in rows)
    s_total = sum(r["summary_total"] for r in rows)
    metrics = {
        "messages": len(rows),
        "type": rate(sum(slot_types), len(slot_types)),
        "color": rate(sum(slot_colors), len(slot_colors)),
        "accessories": rate(sum(r["accessories"] for r in rows), len(rows)),
        "negatives": rate(sum(r["negatives"] for r in rows), len(rows)),
        "all_fields": rate(sum(r["all"] for r in rows), len(rows)),
        "hallucination": {"count": halluc, "predicted": predicted, "rate": round(halluc / predicted, 4) if predicted else 0.0},
        "summary_ungrounded": {"count": sum(r["summary_ungrounded"] for r in rows), "total": s_total,
                               "rate": round(sum(r["summary_ungrounded"] for r in rows) / s_total, 4) if s_total else 0.0},
    }
    wrong = {sn: _wrong_fields(r) for sn, r in per.items() if not r["all"]}
    return metrics, wrong


def _wrong_fields(r):
    out = [f"{s}.{k}" for s, v in r["slots"].items() for k, ok in v.items() if ok is False]
    return out + [f for f in ("accessories", "negatives") if not r[f]]


ROWS = [("옷 종류", "type"), ("색상", "color"), ("소지품", "accessories"), ("부정 표현", "negatives"), ("전체 필드", "all_fields")]


def _fmt_rate(m):
    return "-" if m["accuracy"] is None else f"{m['accuracy'] * 100:5.1f}% ({m['correct']}/{m['total']})"


def print_table(results):
    """results: {이름: metrics}. 이름별로 열을 만든다."""
    names = list(results)
    print(f"{'항목':<14}" + "".join(f"{n:>22}" for n in names))
    for label, key in ROWS:
        print(f"{label:<14}" + "".join(f"{_fmt_rate(results[n][key]):>22}" for n in names))
    print(f"{'환각(낮을수록 좋음)':<10}" + "".join(
        f"{results[n]['hallucination']['rate'] * 100:5.1f}% ({results[n]['hallucination']['count']}/{results[n]['hallucination']['predicted']})".rjust(22)
        for n in names))
    print(f"{'요약 근거 없음':<12}" + "".join(
        f"{results[n]['summary_ungrounded']['rate'] * 100:5.1f}% ({results[n]['summary_ungrounded']['count']}/{results[n]['summary_ungrounded']['total']})".rjust(22)
        for n in names))


def save(name, payload):
    """results/eval-<name>-<시각>.json 으로 저장. 원문은 넣지 않는다."""
    RESULTS_DIR.mkdir(exist_ok=True)
    path = RESULTS_DIR / f"eval-{name}-{datetime.now():%Y%m%d-%H%M%S}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def self_test(golds):
    """정답을 그대로 넣으면 모든 항목이 100%, 환각 0%인지."""
    metrics, wrong = evaluate(golds, golds)
    ok = all(metrics[k]["accuracy"] in (1.0, None) for _, k in ROWS) and metrics["hallucination"]["count"] == 0 and not wrong
    return ok, metrics
