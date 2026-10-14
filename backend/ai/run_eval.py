"""옷차림 추출 평가 실행. 저장소 폴더에서:

    python -m backend.ai.run_eval --mode rule                  # 규칙 추출 (키 필요 없음), 기본 데이터 sample
    python -m backend.ai.run_eval --mode ai --dataset eval     # Gemini (GEMINI_API_KEY 필요)
    python -m backend.ai.run_eval --mode both --dataset all    # 둘 다, 데이터 전체
    python -m backend.ai.run_eval --mode ai --dataset eval --fresh   # AI 캐시를 무시하고 처음부터

AI 모드는 문자마다 결과를 results/ai-cache-*.json 에 바로 저장한다. 도중에 멈추면(예: 429가 계속될 때)
같은 명령으로 다시 실행하면 받은 건 건너뛰고 이어서 진행한다. 호출 사이 간격은 .env의 GEMINI_CALL_INTERVAL_SEC(기본 4초).

--dataset
  sample: disaster-messages.json (45건: 실종 35 + 실종 아님 10). 규칙 단어 목록과 같은 사람이 만든 데이터.
  eval:   disaster-messages-eval.json (15건, 모두 실종). 규칙을 만든 사람이 보지 않은 표현으로 쓴 평가용 데이터.
  all:    둘을 합친 것.
대상은 정답에서 실종 문자인 것. 실종 아닌 문자는 "제외 판단 정확도"로 따로 본다.
결과 표를 출력하고 results/ 에 JSON으로 저장한다 (원문은 저장하지 않음).
"""
import argparse
import hashlib
import json
import time
from pathlib import Path

from . import evaluate, extract_rule
from .schema import AI_RESPONSE_SCHEMA, label_to_output

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


def exclusion_accuracy(judged, labels):
    """실종 문자인지 판단(judged: {SN: True/False})이 정답과 맞는지."""
    rows = [(judged[sn], l["is_missing"]) for sn, l in labels.items()]
    return {
        "total": len(rows),
        "correct": sum(p == g for p, g in rows),
        "non_missing_excluded": f"{sum(not p and not g for p, g in rows)}/{sum(not g for _, g in rows)}",
        "missing_kept": f"{sum(p and g for p, g in rows)}/{sum(g for _, g in rows)}",
        "missing_not_recognized_SN": [sn for sn, l in labels.items() if l["is_missing"] and not judged[sn]],
        "wrongly_kept_SN": [sn for sn, l in labels.items() if not l["is_missing"] and judged[sn]],
    }


def run_rule(msgs, labels):
    judged = {sn: extract_rule.is_missing_message(msgs[sn]) for sn in labels}
    preds = {sn: extract_rule.extract(msgs[sn]) for sn, l in labels.items() if l["is_missing"]}
    return preds, judged


def _cache_path():
    """모델·프롬프트·응답 형식이 같을 때만 같은 캐시를 쓴다 (하나라도 바뀌면 새 파일)."""
    from . import extract_ai
    key = hashlib.sha256((extract_ai.model_name() + extract_ai.PROMPT +
                          json.dumps(AI_RESPONSE_SCHEMA, sort_keys=True)).encode()).hexdigest()[:10]
    return evaluate.RESULTS_DIR / f"ai-cache-{extract_ai.model_name()}-{key}.json"


def run_ai(msgs, labels, fresh=False):
    """모든 문자에 AI를 부른다 (실종 판단 정확도를 보려고 실종 아닌 문자도 부른다).

    문자마다 결과를 results/ 캐시에 바로 저장하고, 다시 실행하면 이미 받은 문자는 건너뛴다.
    캐시에는 AI 결과(옷차림 항목)만 있고 문자 원문·키는 없다.
    """
    from . import extract_ai
    client = extract_ai.get_client()  # 키가 없으면 여기서 안내 문구로 끝난다
    path = _cache_path()
    cache = {} if fresh or not path.exists() else json.loads(path.read_text(encoding="utf-8"))
    interval = extract_ai.call_interval()
    todo = [sn for sn in labels if str(sn) not in cache]
    print(f"AI 모델 {extract_ai.model_name()} | 캐시 {path.name}: 이미 받은 {len(labels) - len(todo)}건, "
          f"새로 부를 {len(todo)}건 | 호출 간격 {interval:g}초")
    for i, sn in enumerate(todo, 1):
        if i > 1:
            time.sleep(interval)
        try:
            out, dropped, is_missing = extract_ai.extract(client, msgs[sn], log=lambda m, sn=sn: print(f"  SN {sn}: {m}"))
        except extract_ai.AIError as e:
            raise SystemExit(f"[오류] {i}/{len(todo)}번째 문자(SN {sn})에서 멈춤: {e}\n"
                             f"  지금까지 받은 {len(cache)}건은 저장돼 있어, 같은 명령으로 다시 실행하면 이어서 진행합니다.")
        cache[str(sn)] = {"output": out, "dropped": dropped, "is_missing": is_missing}
        evaluate.RESULTS_DIR.mkdir(exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
        print(f"  [{i}/{len(todo)}] SN {sn} 완료")
    dropped = sum(cache[str(sn)]["dropped"] for sn in labels)
    print(f"근거가 원문에 없어 버린 항목 {dropped}개\n")
    preds = {sn: cache[str(sn)]["output"] for sn, l in labels.items() if l["is_missing"]}
    judged = {sn: cache[str(sn)]["is_missing"] for sn in labels}
    return preds, judged


def main():
    p = argparse.ArgumentParser(description="재난문자 옷차림 추출 평가")
    p.add_argument("--mode", choices=["rule", "ai", "both"], default="rule")
    p.add_argument("--dataset", choices=["sample", "eval", "all"], default="sample")
    p.add_argument("--no-save", action="store_true", help="results/ 에 저장하지 않음")
    p.add_argument("--fresh", action="store_true", help="AI 캐시를 쓰지 않고 처음부터 다시 부름")
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

    runs, exclusions = {}, {}
    if args.mode in ("rule", "both"):
        runs["rule"], judged = run_rule(msgs, labels)
        exclusions["rule"] = exclusion_accuracy(judged, labels)
    if args.mode in ("ai", "both"):
        runs["ai"], judged = run_ai(msgs, labels, fresh=args.fresh)
        exclusions["ai"] = exclusion_accuracy(judged, labels)

    print(f"데이터 {args.dataset} | 평가 대상: 실종 문자 {len(targets)}건 (전체 {len(labels)}건)")
    for name, excl in exclusions.items():
        print(f"[{name}] 실종 문자 판단: {excl['correct']}/{excl['total']} 맞음 "
              f"(실종 문자 유지 {excl['missing_kept']}, 실종 아닌 문자 제외 {excl['non_missing_excluded']})")
        if excl["missing_not_recognized_SN"]:
            print(f"  실종 문자인데 알아보지 못한 SN: {excl['missing_not_recognized_SN']}")
        if excl["wrongly_kept_SN"]:
            print(f"  실종 문자가 아닌데 실종으로 본 SN: {excl['wrongly_kept_SN']}")
    print()

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
        payload = {"mode": args.mode, "dataset": args.dataset, "exclusion": exclusions,
                   "results": {name: {"metrics": m, "wrong_fields_by_SN": {str(k): v for k, v in w.items()},
                                      "by_hard_case": hard[name]}
                               for name, (m, w) in results.items()}}
        print(f"\n저장: {evaluate.save(f'{args.mode}-{args.dataset}', payload).relative_to(DATA.parent)}")


if __name__ == "__main__":
    main()
