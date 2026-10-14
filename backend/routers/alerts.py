"""실종경보 API와 시연용 API.

원본 필드는 그대로 두고 status, found_at, ended_at, issued_at, target_label, photo_url, source, is_sample, ai만 덧붙인다.
ai는 상세·시연용 응답에서 {status, clothing, summary, extracted_at}, 목록에서 {status, summary} (services/ai_features).
source와 is_sample은 데이터를 읽어 온 모듈(source)이 정한다.
시연용 상태(발령·발견)는 메모리에만 있어서 서버를 다시 켜면 처음 상태로 돌아간다.
"""
from datetime import datetime, timedelta, timezone
from enum import Enum

from fastapi import APIRouter, Depends, HTTPException, Query

from services import ai_features, push
from services.data_source import source  # .env의 DATA_SOURCE로 가상(sample)·실제(safe182) 선택

KST = timezone(timedelta(hours=9))
FOUND_VISIBLE = timedelta(days=3)  # 발견 완료·경보종료 후 목록·상세에 남아 있는 기간

# 안전Dream 대상구분 코드 → 화면용 이름 (모르는 코드는 "기타")
TARGET_LABELS = {
    "010": "아동",
    "060": "지적장애인",
    "061": "지적장애인(18세 미만)",
    "062": "지적장애인(18세 이상)",
    "070": "치매환자",
}


class Status(str, Enum):
    searching = "수색중"
    ended = "경보종료"  # 실제 모드에서 목록에서 3번 연속 빠진 경보, 시연용 /test/end
    found = "발견완료"  # 시연용 /test/found만


router = APIRouter()
_state = {}  # msspsnIdntfccd → {"status", "issued_at", "found_at", "ended_at"} (시연용 변경분)


def _now():
    return datetime.now(KST)


def _parse_occrde(value):
    """발생일(YYYYMMDD)을 KST 0시 datetime으로 바꾼다. 누락·형식 오류·없는 날짜면 None."""
    text = str(value).strip() if value is not None else ""
    if len(text) != 8 or not text.isdigit():
        return None
    try:
        return datetime.strptime(text, "%Y%m%d").replace(tzinfo=KST)
    except ValueError:  # 20260230처럼 없는 날짜
        return None


def _issued_at(raw):
    """시연용으로 다시 발령한 시각, 없으면 발생일 0시, 발생일도 잘못됐으면 None."""
    st = _state.get(raw["msspsnIdntfccd"], {})
    return st.get("issued_at") or _parse_occrde(raw.get("occrde"))


def _enrich(raw, full_ai=True):
    """원본 항목에 추가 필드를 붙인다. 원본 딕셔너리는 바꾸지 않는다. full_ai=False면 목록용 ai."""
    sid = raw["msspsnIdntfccd"]
    st = _state.get(sid, {})
    issued = _issued_at(raw)
    status = st.get("status", source.status_of(raw))
    hidden = {"nm": None, "tknphotoFile": None, "tknphotolength": 0} if status == Status.ended.value else {}
    return {
        **raw,
        **hidden,  # 경보종료는 이름·사진 제외 (실제 모드 sync.snapshot과 같은 규칙)
        "occrAdres": (raw.get("occrAdres") or "").strip(),
        "status": status,
        "issued_at": issued.isoformat() if issued else None,
        "found_at": st["found_at"].isoformat() if st.get("found_at") else None,
        "ended_at": st["ended_at"].isoformat() if st.get("ended_at") else None,
        "target_label": TARGET_LABELS.get(raw.get("writngTrgetDscd"), "기타"),
        "photo_url": None,
        "source": source.SOURCE,
        "is_sample": source.IS_SAMPLE,
        "ai": ai_features.view(sid, full=full_ai),
    }


def _expired(st):
    done = st.get("found_at") or st.get("ended_at")
    return done is not None and _now() - done > FOUND_VISIBLE


def _find(sid):
    raws, notice = source.load_alerts()
    raw = next((r for r in raws if r["msspsnIdntfccd"] == sid), None)
    if raw is None:
        raise HTTPException(404, notice or f"경보 {sid}를 찾을 수 없습니다")
    return raw


@router.get("/alerts", tags=["alerts"], summary="경보 목록")
def list_alerts(
    days: int | None = Query(None, ge=1, le=36500, description="최근 며칠 안에 발령된 경보만 (생략하면 전체)"),
    status: Status | None = Query(None, description="수색중 / 경보종료(실제 모드, 시연용 /test/end) / 발견완료(시연용)"),
):
    raws, notice = source.load_alerts()
    # 가상 데이터는 발생일이 고정이라, 기본값으로 날짜를 거르면 시간이 지나 목록이 비어 버린다.
    since = _now() - timedelta(days=days) if days is not None else None
    rows = []
    for raw in raws:
        if _expired(_state.get(raw["msspsnIdntfccd"], {})):
            continue
        issued = _issued_at(raw)
        if since is not None and (issued is None or issued < since):  # 날짜를 모르면 거를 수 없어 뺀다
            continue
        item = _enrich(raw, full_ai=False)
        if status and item["status"] != status.value:
            continue
        rows.append((issued, item))
    # 최근 발령 순, 날짜를 모르는 경보는 맨 뒤
    rows.sort(key=lambda r: (r[0] is not None, r[0] or datetime.min.replace(tzinfo=KST)), reverse=True)
    items = [item for _, item in rows]
    return {"notice": notice, "is_sample": source.IS_SAMPLE, "totalCount": len(items), "list": items}


@router.get("/alerts/{sid}", tags=["alerts"], summary="경보 상세")
def get_alert(sid: int):
    raw = _find(sid)
    if _expired(_state.get(sid, {})):
        raise HTTPException(404, f"경보 {sid}는 발견 완료·경보종료 후 3일이 지나 내려갔습니다")
    return _enrich(raw)


def _sample_only():
    """실제 데이터 모드에서는 가짜 경보를 만들거나 바꿀 수 없게 막는다."""
    if not source.IS_SAMPLE:
        raise HTTPException(403, "시연용 API는 가상 데이터 모드(DATA_SOURCE=sample)에서만 쓸 수 있습니다")


@router.post("/test/fire/{sid}", tags=["test"], summary="시연용: 방금 발령된 새 경보로 만들기",
             dependencies=[Depends(_sample_only)])
def test_fire(sid: int):
    _find(sid)
    _state[sid] = {"status": Status.searching.value, "issued_at": _now(), "found_at": None, "ended_at": None}
    ai_features.submit([_find(sid)])  # 옷차림 추출은 기다리지 않음 (캐시에 있으면 바로 done)
    item = _enrich(_find(sid))
    return {**item, "push": push.send("issued", item, item["status"], dedup=True)}


@router.post("/test/found/{sid}", tags=["test"], summary="시연용: 발견 완료로 바꾸기",
             dependencies=[Depends(_sample_only)])
def test_found(sid: int):
    _find(sid)
    _state.setdefault(sid, {}).update(status=Status.found.value, found_at=_now(), ended_at=None)
    item = _enrich(_find(sid))
    return {**item, "push": push.send("closed", item, item["status"], dedup=True)}


@router.post("/test/end/{sid}", tags=["test"], summary="시연용: 경보종료로 바꾸기",
             dependencies=[Depends(_sample_only)])
def test_end(sid: int):
    _find(sid)
    _state.setdefault(sid, {}).update(status=Status.ended.value, found_at=None, ended_at=_now())
    item = _enrich(_find(sid))
    return {**item, "push": push.send("closed", item, item["status"], dedup=True)}
