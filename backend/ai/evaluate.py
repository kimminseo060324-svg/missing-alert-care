"""추출 결과(규칙 또는 AI)를 정답과 필드별로 비교해 정확도를 계산한다.

비교 기준
- 옷 종류: 띄어쓰기를 무시하고, 같은 옷의 다른 표현(츄리닝=트레이닝, 쓰레빠=슬리퍼, 반팔=반소매 티셔츠, 남방=셔츠 등,
  schema.TYPE_SYNONYMS)을 같게 본 뒤, 같거나 한쪽이 다른 쪽을 포함하면 정답 (예: 블라우스 ⊂ 꽃무늬 블라우스).
  upper·lower·shoes 3칸 × 문자 수. 둘 다 비어 있으면 정답.
- 색상: 정답에 색이 적혀 있는 칸만 채점한다. 표준색이 같으면 정답. 정답에 색이 없는 칸("색 정보 없음")은 채점에서 뺀다.
- 소지품·부정 표현: 문자마다 항목 묶음이 정답과 같으면 정답 (소지품 색도 정답에 색이 있을 때만 본다).
- 전체 필드: 문자 하나의 옷 3칸(종류, 채점하는 색), 소지품, 부정 표현이 모두 맞으면 정답.
- 환각: 결과에 넣은 항목(옷 칸·소지품·부정 표현, 그리고 정답에 색이 없는 칸에 붙인 색) 중
  정답에 없는 것의 비율. 낮을수록 좋다. 색을 채점에서 빼는 칸이라도 색을 지어내면 여기서 잡는다.
- 요약 옷·소지품 일치: summary 문구 중 정답의 옷·소지품 항목(상의·하의·신발·소지품 종류)을 가리키는 것의 비율.
  summary는 정답이 따로 없어서, 길에서 알아볼 옷·소지품을 짚었는지로 본다. 나이·성별·키처럼 옷·소지품이 아닌 문구나
  정답에 없는 항목을 짚은 문구는 맞지 않는 것으로 센다. 표현이 달라도(남색잠퍼 ↔ 남색 점퍼) 같은 항목이면 맞다고 본다.
"""
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from .schema import SLOTS, canonical_type, normalize_color, type_in_evidence

RESULTS_DIR = Path(__file__).resolve().parents[2] / "results"


def type_match(pred, gold):
    p, g = canonical_type(pred), canonical_type(gold)
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


def compare(pred, gold):
    """문자 하나 비교. 필드별 맞음 여부와 환각 수를 돌려준다."""
    r = {"slots": {}, "hallucinated": 0, "predicted": 0, "summary_total": 0, "summary_ungrounded": 0}
    def invented_color(p_color, g_color):  # 정답에 색이 없는데 색을 붙였는가
        return bool(normalize_color(p_color)) and not normalize_color(g_color)

    for s in SLOTS:
        p, g = pred[s], gold[s]
        t_ok = (not p["type"] and not g["type"]) or (bool(p["type"]) and bool(g["type"]) and type_match(p["type"], g["type"]))
        c_ok = normalize_color(p["color"]) == normalize_color(g["color"]) if normalize_color(g["color"]) else None
        r["slots"][s] = {"type": t_ok, "color": c_ok}
        if p["type"]:
            r["predicted"] += 1
            r["hallucinated"] += not g["type"] or not type_match(p["type"], g["type"])
        if invented_color(p["color"], g["color"]):
            r["predicted"] += 1
            r["hallucinated"] += 1

    pairs, extra, missing = _match_list(pred["accessories"], gold["accessories"], key=lambda x: x["type"])
    r["accessories"] = not extra and not missing and all(
        normalize_color(p["color"]) == normalize_color(g["color"]) for p, g in pairs if normalize_color(g["color"]))
    r["predicted"] += len(pred["accessories"])
    r["hallucinated"] += len(extra)
    for p, g in pairs:
        if invented_color(p["color"], g["color"]):
            r["predicted"] += 1
            r["hallucinated"] += 1

    _, extra_n, missing_n = _match_list(pred["negatives"], gold["negatives"])
    r["negatives"] = not extra_n and not missing_n
    r["predicted"] += len(pred["negatives"])
    r["hallucinated"] += len(extra_n)

    r["all"] = all(v["type"] and v["color"] is not False for v in r["slots"].values()) and r["accessories"] and r["negatives"]
    gold_items = [gold[s]["type"] for s in SLOTS if gold[s]["type"]] + [a["type"] for a in gold["accessories"]]
    summary = pred.get("summary") or []
    r["summary_total"] = len(summary)
    r["summary_on_items"] = sum(any(type_in_evidence(g, s) for g in gold_items) for s in summary)
    return r


def evaluate(preds, golds):
    """preds, golds: {SN: 출력 형식}."""
    per = {sn: compare(preds[sn], golds[sn]) for sn in golds}
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
        "summary_on_items": {"count": sum(r["summary_on_items"] for r in rows), "total": s_total,
                             "rate": round(sum(r["summary_on_items"] for r in rows) / s_total, 4) if s_total else None},
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
    def summary_cell(m):
        s = m["summary_on_items"]
        return "-" if s["rate"] is None else f"{s['rate'] * 100:5.1f}% ({s['count']}/{s['total']})"
    print(f"{'요약 옷·소지품 일치':<10}" + "".join(summary_cell(results[n]).rjust(22) for n in names))


def save(name, payload):
    """results/eval-<name>-<시각>.json 으로 저장. 원문은 넣지 않는다."""
    RESULTS_DIR.mkdir(exist_ok=True)
    path = RESULTS_DIR / f"eval-{name}-{datetime.now():%Y%m%d-%H%M%S}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def by_hard_case(wrong, labels):
    """특이 표현(hard_cases)별로 (문자 수, 틀린 문자 수, 틀린 칸 목록)을 모은다. 특이 표현이 없는 문자는 "(없음)"."""
    groups = defaultdict(lambda: {"messages": 0, "wrong": 0, "fields": []})
    for sn, label in labels.items():
        for tag in label.get("hard_cases") or ["(없음)"]:
            g = groups[tag]
            g["messages"] += 1
            if sn in wrong:
                g["wrong"] += 1
                g["fields"] += wrong[sn]
    return dict(sorted(groups.items(), key=lambda kv: -kv[1]["messages"]))


def print_hard_cases(groups):
    print(f"{'특이 표현':<10}{'문자':>6}{'틀림':>6}  틀린 칸")
    for tag, g in groups.items():
        fields = ", ".join(f"{f}×{g['fields'].count(f)}" for f in sorted(set(g["fields"]))) or "-"
        print(f"{tag:<10}{g['messages']:>6}{g['wrong']:>6}  {fields}")


def self_test(golds):
    """정답을 그대로 넣으면 모든 항목이 100%, 환각 0%인지."""
    metrics, wrong = evaluate(golds, golds)
    ok = all(metrics[k]["accuracy"] in (1.0, None) for _, k in ROWS) and metrics["hallucination"]["count"] == 0 and not wrong
    return ok, metrics
