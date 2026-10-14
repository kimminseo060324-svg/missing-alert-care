"""옷차림 추출 평가 실행. 저장소 폴더에서:

    python -m backend.ai.run_eval --mode rule                  # 규칙 추출 (키 필요 없음), 기본 데이터 sample
    python -m backend.ai.run_eval --mode ai --dataset eval     # Gemini (GEMINI_API_KEY 필요)
    python -m backend.ai.run_eval --mode both --dataset all    # 둘 다, 데이터 전체

--dataset
  sample: disaster-messages.json (45건: 실종 35 + 실종 아님 10). 규칙 단어 목록과 같은 사람이 만든 데이터.
  eval:   disaster-messages-eval.json (15건, 모두 실종). 규칙을 만든 사람이 보지 않은 표현으로 쓴 평가용 데이터.
  all:    둘을 합친 것.
대상은 정답에서 실종 문자인 것. 실종 아닌 문자는 "제외 판단 정확도"로 따로 본다.
결과 표를 출력하고 results/ 에 JSON으로 저장한다 (원문은 저장하지 않음).
"""
import argparse
import json
from pathlib import Path

from . import evaluate, extract_rule
from .schema import label_to_output

DATA = Path(__file__).resolve().parents[2] / "sample-data"
DATASETS = {
    "sample": ("disaster-messages.json", "disaster-messages-labels.json"),
    "eval": ("disaster-messages-eval.json", "disaster-messages-eval-labels.json"),
}


def load(dataset="sample"):
    msgs, labels = {}, {}
    for name in (DATASETS if dataset == "all" else [dataset]):
        msg_file, label_file = DATASETS[name]
        msgs.update({m["SN"]: m["MSG_CN"] for m in json.loads((DATA / msg_file).read_text(encoding="utf-8"))["body"]})
        labels.update({l["SN"]: l for l in json.loads((DATA / label_file).read_text(encoding="utf-8"))["labels"]})
    return msgs, labels


def exclusion_accuracy(msgs, labels):
    """실종 문자인지 판단(extract_rule.is_missing_message)이 정답과 맞는지."""
    rows = [(extract_rule.is_missing_message(msgs[sn]), l["is_missing"]) for sn, l in labels.items()]
    missed = [sn for sn, l in labels.items() if l["is_missing"] and not extract_rule.is_missing_message(msgs[sn])]
    return {
        "total": len(rows),
        "correct": sum(p == g for p, g in rows),
        "non_missing_excluded": f"{sum(not p and not g for p, g in rows)}/{sum(not g for _, g in rows)}",
        "missing_kept": f"{sum(p and g for p, g in rows)}/{sum(g for _, g in rows)}",
        "missing_not_recognized_SN": missed,
    }


def run_rule(msgs, targets):
    return {sn: extract_rule.extract(msgs[sn]) for sn in targets}


def run_ai(msgs, targets):
    from . import extract_ai
    client = extract_ai.get_client()  # 키가 없으면 여기서 안내 문구로 끝난다
    preds, dropped = {}, 0
    for i, sn in enumerate(targets, 1):
        try:
            out, d = extract_ai.extract(client, msgs[sn])
        except extract_ai.AIError as e:
            raise SystemExit(f"[오류] {i}번째 문자(SN {sn})에서 멈춤: {e}")
        preds[sn], dropped = out, dropped + d
    print(f"AI 모델 {extract_ai.model_name()} | 근거가 원문에 없어 버린 항목 {dropped}개")
    return preds


def main():
    p = argparse.ArgumentParser(description="재난문자 옷차림 추출 평가")
    p.add_argument("--mode", choices=["rule", "ai", "both"], default="rule")
    p.add_argument("--dataset", choices=["sample", "eval", "all"], default="sample")
    p.add_argument("--no-save", action="store_true", help="results/ 에 저장하지 않음")
    args = p.parse_args()

    if args.mode in ("ai", "both"):
        from . import extract_ai
        extract_ai.get_client()  # 키가 없으면 규칙 결과를 계산하기 전에 바로 안내하고 끝낸다

    msgs, labels = load(args.dataset)
    targets = [sn for sn, l in labels.items() if l["is_missing"]]
    golds = {sn: label_to_output(labels[sn]) for sn in targets}

    ok, _ = evaluate.self_test(golds)
    if not ok:
        raise SystemExit("[오류] 평가 코드 자체 점검 실패: 정답을 넣어도 100%가 나오지 않습니다")

    excl = exclusion_accuracy(msgs, labels)
    print(f"데이터 {args.dataset} | 제외 판단: {excl['correct']}/{excl['total']} 맞음 "
          f"(실종 아닌 문자 제외 {excl['non_missing_excluded']}, 실종 문자 유지 {excl['missing_kept']})")
    if excl["missing_not_recognized_SN"]:
        print(f"  실종 문자인데 실종으로 알아보지 못한 SN: {excl['missing_not_recognized_SN']}")
    print(f"평가 대상: 실종 문자 {len(targets)}건\n")

    runs = {}
    if args.mode in ("rule", "both"):
        runs["rule"] = run_rule(msgs, targets)
    if args.mode in ("ai", "both"):
        runs["ai"] = run_ai(msgs, targets)

    texts = {sn: msgs[sn] for sn in targets}
    results = {name: evaluate.evaluate(preds, golds, texts) for name, preds in runs.items()}
    evaluate.print_table({name: m for name, (m, _) in results.items()})

    target_labels = {sn: labels[sn] for sn in targets}
    hard = {}
    for name, (_, wrong) in results.items():
        hard[name] = evaluate.by_hard_case(wrong, target_labels)
        print(f"\n[{name}] 특이 표현별")
        evaluate.print_hard_cases(hard[name])

    if not args.no_save:
        payload = {"mode": args.mode, "dataset": args.dataset, "exclusion": excl,
                   "results": {name: {"metrics": m, "wrong_fields_by_SN": {str(k): v for k, v in w.items()},
                                      "by_hard_case": hard[name]}
                               for name, (m, w) in results.items()}}
        print(f"\n저장: {evaluate.save(f'{args.mode}-{args.dataset}', payload).relative_to(DATA.parent)}")


if __name__ == "__main__":
    main()
