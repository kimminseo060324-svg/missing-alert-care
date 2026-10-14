"""경보별 AI 옷차림 특징 (backend/ai의 Gemini 추출을 서버에 연결).

- 경보가 들어오면(샘플 로드, sync 신규, /test/fire) submit()으로 넣는다. 기다리지 않고 바로 돌아온다.
- 추출은 asyncio 백그라운드 태스크 하나가 순서대로 한다. 실제 호출 사이에는 GEMINI_CALL_INTERVAL_SEC만큼 쉰다.
  Gemini SDK는 동기 함수라 데몬 스레드에서 부른다 (asyncio.to_thread를 쓰면 서버를 끌 때 진행 중인 호출이
  재시도 대기까지 끝날 때까지 종료가 멈춘다).
- AI에 보내는 글: sample은 같은 사람의 가상 재난문자(disaster-messages-labels.json의 linked_msspsnIdntfccd),
  safe182는 재난문자 연동이 없어 보낼 글이 없다 → unavailable.
- 캐시: 개인정보를 지운 문장(preprocess.redact)의 sha256 → 결과. 메모리 기본,
  DATA_SOURCE=sample일 때만 results/ai_cache.json에도 저장한다 (safe182는 파일 저장 금지).
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
_cache = {}  # sha256(개인정보 지운 문장) → {"clothing", "summary", "extracted_at"}
_waiting = {}  # 추출 대기 중인 키 → (문장, [식별번호])
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


def _key(text):
    return hashlib.sha256(redact(text).encode("utf-8")).hexdigest()


def _label(item):
    """{type, color} → "회색 점퍼" (색이 없으면 "지팡이"). 이미 문자열이면 그대로."""
    if isinstance(item, str):
        return item
    return f"{item.get('color') or ''} {item.get('type') or ''}".strip()


def _labels(clothing):
    """옷 칸마다 문자열 목록으로. 예전 형식({type, color})으로 저장된 캐시도 이걸로 바꾼다."""
    return {s: [x for x in map(_label, clothing.get(s) or []) if x] for s in SLOTS}


def _to_result(out):
    """extract_ai.verify 출력 → 응답 모양 (옷 칸은 "색 종류" 문자열 목록, 요약은 최대 3개)."""
    clothing = {s: [out[s]] if out.get(s, {}).get("type") else [] for s in ("upper", "lower", "shoes")}
    clothing["accessories"] = list(out.get("accessories") or [])
    clothing = _labels(clothing)
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
                if _results.get(sid, {}).get("status") != "done":
                    _results[sid] = _empty("unavailable")
            continue
        key = _key(text)
        with _lock:
            if key in _cache:
                _results[sid] = {"status": "done", **_cache[key]}
                continue
            _results[sid] = _empty("pending")
            if key in _waiting:
                _waiting[key][1].append(sid)
                continue
            _waiting[key] = (text, [sid])
        try:
            _loop.call_soon_threadsafe(_queue.put_nowait, key)
        except (RuntimeError, AttributeError):  # 서버가 꺼지는 중 (루프가 닫힘)
            with _lock:
                _waiting.pop(key, None)
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
            text, _ = _waiting.get(key, (None, []))
        if text is None:
            continue
        if called:
            await asyncio.sleep(extract_ai.call_interval())
        called = True
        result = await _in_daemon_thread(_extract_safe, text)
        with _lock:
            _, sids = _waiting.pop(key, (None, []))
            for sid in sids:
                _results[sid] = {"status": "done", **result} if result else _empty("unavailable")
            if result:
                _cache[key] = result
                snapshot = dict(_cache)
        if result and _save_file():
            _write_cache(snapshot)
        log.info("AI 추출 %s (경보 %d건)", "완료" if result else "실패", len(sids))


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
            with _lock:
                for key, r in json.loads(CACHE_PATH.read_text(encoding="utf-8")).items():
                    _cache[key] = {**r, "clothing": _labels(r.get("clothing") or {})}
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
