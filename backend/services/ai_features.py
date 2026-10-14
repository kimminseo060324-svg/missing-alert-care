"""경보별 AI 옷차림 특징 (backend/ai의 Gemini 추출을 서버에 연결).

- 경보가 들어오면(샘플 로드, sync 신규, /test/fire) submit()으로 넣는다. 기다리지 않고 바로 돌아온다.
- 추출은 asyncio 백그라운드 태스크 하나가 순서대로 한다. 실제 호출 사이에는 GEMINI_CALL_INTERVAL_SEC만큼 쉰다.
  Gemini SDK는 동기 함수라 데몬 스레드에서 부른다 (asyncio.to_thread를 쓰면 서버를 끌 때 진행 중인 호출이
  재시도 대기까지 끝날 때까지 종료가 멈춘다).
- AI에 보내는 글: sample은 같은 사람의 가상 재난문자(disaster-messages-labels.json의 linked_msspsnIdntfccd),
  safe182는 재난문자 연동이 없어 보낼 글이 없다 → unavailable.
- 캐시 키: sha256(설정 해시 + 개인정보를 지운 문장(preprocess.redact)).
  설정 해시 = sha256(모델명 + 프롬프트 해시 + JSON 스키마 해시). 프롬프트·스키마는 extract_ai에 있는 실제 값으로
  계산하므로, 모델(GEMINI_MODEL)·프롬프트·스키마 중 하나라도 바뀌면 키가 바뀌어 새로 추출한다 (버전 번호 불필요).
- 캐시는 메모리 기본, DATA_SOURCE=sample일 때만 results/ai_cache.json에도 저장한다 (safe182는 파일 저장 금지).
  파일에는 항목마다 설정 해시만 함께 저장한다 (모델명·프롬프트 원문은 저장하지 않음).
  읽을 때 설정 해시가 지금과 다르거나 없거나 모양이 틀린 항목은 버린다 → 새로 추출.
- 경보마다 마지막 요청의 캐시 키를 기억한다(_current). 작업이 끝났을 때 그 경보의 마지막 요청 키와 같을 때만
  결과를 반영한다. 먼저 시작한 작업이 늦게 끝나 최신 결과(예: 문자 내용이 바뀐 뒤의 요청)를 덮어쓰지 않게 하려는 것.
  버린 결과도 캐시에는 키 기준으로 넣는다.
- AI_EXTRACT_ENABLED(기본 sample=1, safe182=0)가 꺼져 있거나 GEMINI_API_KEY가 없거나 호출이 실패하면 unavailable.
  예외는 밖으로 내보내지 않고, 로그에는 건수·오류 종류만 남긴다 (원문·키·응답 없음).
"""
import asyncio
import hashlib
import json
import logging
import os
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ai import extract_ai
from ai.preprocess import redact
from services.data_source import MODE

KST = timezone(timedelta(hours=9))
ROOT = Path(__file__).resolve().parents[2]
CACHE_PATH = ROOT / "results" / "ai_cache.json"
SAMPLE_DIR = ROOT / "sample-data"
SLOTS = ("upper", "lower", "shoes", "accessories")

log = logging.getLogger("ai-features")
if not log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(asctime)s [ai-features] %(levelname)s %(message)s"))
    log.addHandler(_h)
    log.setLevel(logging.INFO)
    log.propagate = False

_lock = threading.Lock()
_results = {}  # 식별번호 → {"status", "clothing", "summary", "extracted_at"}
_cache = {}  # 캐시 키 → (설정 해시, {"clothing", "summary", "extracted_at"})
_waiting = {}  # 추출 대기 중인 키 → (문장, 설정 해시, [식별번호])
_current = {}  # 식별번호 → 마지막 요청의 캐시 키 (보낼 글이 없으면 없음)
_loop = None
_queue = None
_task = None
_texts = None  # sample: 식별번호 → 재난문자 원문
_client = None


def enabled():
    default = "1" if MODE == "sample" else "0"
    return (os.getenv("AI_EXTRACT_ENABLED") or default).strip() == "1"


def _save_file():
    return MODE == "sample"


def _empty(status):
    return {"status": status, "clothing": {s: [] for s in SLOTS}, "summary": [], "extracted_at": None}


def view(sid, full=True):
    """응답용 ai 필드. 항상 같은 모양. full=False면 목록용(status, summary)."""
    with _lock:
        r = _results.get(sid) or _empty("unavailable")
        r = {**r, "clothing": {s: list(v) for s, v in r["clothing"].items()}, "summary": list(r["summary"])}
    return r if full else {"status": r["status"], "summary": r["summary"]}


def source_text(raw):
    """AI에 보낼 원문. 없으면 None."""
    global _texts
    if MODE != "sample":
        return None
    if _texts is None:
        try:
            msgs = {m["SN"]: m["MSG_CN"] for m in
                    json.loads((SAMPLE_DIR / "disaster-messages.json").read_text(encoding="utf-8"))["body"]}
            labels = json.loads((SAMPLE_DIR / "disaster-messages-labels.json").read_text(encoding="utf-8"))["labels"]
            _texts = {l["linked_msspsnIdntfccd"]: msgs[l["SN"]] for l in labels
                      if l.get("linked_msspsnIdntfccd") and l["SN"] in msgs}
        except (OSError, ValueError, KeyError, TypeError) as e:
            log.warning("가상 재난문자를 읽지 못했습니다 (%s)", type(e).__name__)
            _texts = {}
    return _texts.get(raw.get("msspsnIdntfccd"))


def _sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def config_hash():
    """지금 쓰는 모델명·프롬프트·JSON 스키마의 해시. 코드나 GEMINI_MODEL이 바뀌면 값이 바뀐다.
    프롬프트는 템플릿(PROMPT)이 아니라 실제로 보내는 모양(build_prompt, 표준 색 목록이 채워진 것)으로 계산한다.
    문장 자리는 비워 두므로 경보마다 달라지지 않는다."""
    schema = json.dumps(extract_ai.AI_RESPONSE_SCHEMA, sort_keys=True, ensure_ascii=False)
    prompt = extract_ai.build_prompt("")
    return _sha("\n".join([extract_ai.model_name(), _sha(prompt), _sha(schema)]))


def _key(text, config):
    return _sha(config + "\n" + redact(text))


def _valid(r):
    """캐시 파일 항목이 지금 응답 모양인지 (옷 칸은 문자열 목록, 요약은 3개 이하 문자열 목록)."""
    def strings(v):
        return isinstance(v, list) and all(isinstance(x, str) for x in v)
    c = r.get("clothing")
    return (isinstance(c, dict) and all(strings(c.get(s)) for s in SLOTS)
            and strings(r.get("summary")) and len(r["summary"]) <= 3 and isinstance(r.get("extracted_at"), str))


def _to_result(out):
    """extract_ai.verify 출력 → 응답 모양 (옷 칸은 "색 종류" 문자열 목록, 색이 없으면 종류만. 요약은 최대 3개)."""
    items = {s: [out[s]] if out.get(s, {}).get("type") else [] for s in ("upper", "lower", "shoes")}
    items["accessories"] = list(out.get("accessories") or [])
    clothing = {s: [f"{i.get('color') or ''} {i.get('type') or ''}".strip() for i in items[s]] for s in SLOTS}
    return {"clothing": clothing, "summary": list(out.get("summary") or [])[:3],
            "extracted_at": datetime.now(KST).isoformat()}


def _call_gemini(text):
    """원문 하나 → extract_ai 검증 출력. 테스트에서는 이 함수를 가짜로 바꾼다. 실패하면 예외."""
    global _client
    if _client is None:
        _client = extract_ai.get_client()
    out, _, _ = extract_ai.extract(_client, text, log=lambda m: log.warning("Gemini %s", m))
    return out


def submit(raws):
    """경보들을 추출 대기열에 넣는다. 기다리지 않는다. 캐시에 있으면 바로 done."""
    for raw in raws:
        sid = raw.get("msspsnIdntfccd")
        text = source_text(raw) if enabled() and os.getenv("GEMINI_API_KEY") else None
        if not text or _loop is None:
            with _lock:
                _current.pop(sid, None)  # 진행 중인 예전 요청 결과는 반영하지 않음
                if _results.get(sid, {}).get("status") != "done":
                    _results[sid] = _empty("unavailable")
            continue
        config = config_hash()
        key = _key(text, config)
        with _lock:
            _current[sid] = key
            if key in _cache:
                _results[sid] = {"status": "done", **_cache[key][1]}
                continue
            _results[sid] = _empty("pending")
            if key in _waiting:
                if sid not in _waiting[key][2]:
                    _waiting[key][2].append(sid)
                continue
            _waiting[key] = (text, config, [sid])
        try:
            _loop.call_soon_threadsafe(_queue.put_nowait, key)
        except (RuntimeError, AttributeError):  # 서버가 꺼지는 중 (루프가 닫힘)
            with _lock:
                _waiting.pop(key, None)
                _current.pop(sid, None)
                _results[sid] = _empty("unavailable")


def _extract_safe(text):
    """추출 결과(응답 모양) 또는 실패 시 None. 예외를 밖으로 내지 않는다."""
    try:
        return _to_result(_call_gemini(text))
    except (Exception, SystemExit) as e:  # get_client는 키가 없으면 SystemExit를 낸다. 메시지 대신 종류만
        log.warning("AI 추출 실패 (%s)", type(e).__name__)
        return None


async def _in_daemon_thread(fn, *args):
    """fn(*args)를 데몬 스레드에서 돌리고 결과를 기다린다. 서버 종료는 이 스레드를 기다리지 않는다."""
    loop = asyncio.get_running_loop()
    fut = loop.create_future()

    def run():
        result = fn(*args)
        try:
            loop.call_soon_threadsafe(lambda: fut.done() or fut.set_result(result))
        except RuntimeError:  # 그사이 서버가 꺼져 루프가 닫힘
            pass
    threading.Thread(target=run, name="ai-extract", daemon=True).start()
    return await fut


async def _worker():
    called = False
    while True:
        key = await _queue.get()
        with _lock:
            text, config, _ = _waiting.get(key, (None, None, []))
        if text is None:
            continue
        if called:
            await asyncio.sleep(extract_ai.call_interval())
        called = True
        result = await _in_daemon_thread(_extract_safe, text)
        with _lock:
            _, _, sids = _waiting.pop(key, (None, None, []))
            stale = [sid for sid in sids if _current.get(sid) != key]  # 그사이 새 요청이 들어온 경보
            for sid in sids:
                if sid not in stale:
                    _results[sid] = {"status": "done", **result} if result else _empty("unavailable")
            if result:
                _cache[key] = (config, result)
                snapshot = {k: {"config": c, **r} for k, (c, r) in _cache.items()}
        if result and _save_file():
            _write_cache(snapshot)
        if stale:
            log.info("AI 추출 결과 %d건은 그사이 새 요청이 있어 반영하지 않았습니다", len(stale))
        log.info("AI 추출 %s (경보 %d건)", "완료" if result else "실패", len(sids) - len(stale))


def _write_cache(cache):
    try:
        CACHE_PATH.parent.mkdir(exist_ok=True)
        tmp = CACHE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
        tmp.replace(CACHE_PATH)
    except OSError as e:
        log.warning("AI 캐시 파일을 저장하지 못했습니다 (%s)", type(e).__name__)


def start():
    """서버 시작 시 (이벤트 루프 안에서) 부른다. 멈추는 코루틴 함수를 돌려준다."""
    global _loop, _queue, _task
    if _save_file() and CACHE_PATH.exists():
        try:
            data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            data = data if isinstance(data, dict) else {}
            config, kept = config_hash(), 0
            with _lock:
                for key, r in data.items():
                    # 설정 해시가 다르거나 없거나(예전 형식) 모양이 틀린 항목은 버린다 → 새로 추출
                    if isinstance(r, dict) and r.get("config") == config and _valid(r):
                        _cache[key] = (config, {k: r[k] for k in ("clothing", "summary", "extracted_at")})
                        kept += 1
            if kept < len(data):
                log.info("AI 캐시 %d건 중 %d건은 설정이 다르거나 형식이 맞지 않아 쓰지 않습니다", len(data), len(data) - kept)
        except (OSError, ValueError) as e:
            log.warning("AI 캐시 파일을 읽지 못해 새로 시작합니다 (%s)", type(e).__name__)
    _loop, _queue = asyncio.get_running_loop(), asyncio.Queue()
    _task = asyncio.create_task(_worker())
    if not enabled():
        log.info("AI 옷차림 추출 꺼짐 (AI_EXTRACT_ENABLED)")
    elif not os.getenv("GEMINI_API_KEY"):
        log.info("GEMINI_API_KEY가 없어 AI 옷차림 추출을 하지 않습니다")

    async def stop():
        global _loop
        _loop = None
        _task.cancel()
        try:
            await _task
        except asyncio.CancelledError:
            pass

    return stop
