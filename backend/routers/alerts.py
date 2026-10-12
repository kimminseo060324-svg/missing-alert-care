"""실종경보 API와 시연용 API.

원본 필드는 그대로 두고 status, found_at, issued_at, target_label, photo_url, source만 덧붙인다.
시연용 상태(발령·발견)는 메모리에만 있어서 서버를 다시 켜면 처음 상태로 돌아간다.
"""
from datetime import datetime, timedelta, timezone
from enum import Enum

from fastapi import APIRouter, HTTPException, Query

from services import sample_data as source  # 실제 API로 바꿀 때 이 줄만 교체

KST = timezone(timedelta(hours=9))
FOUND_VISIBLE = timedelta(days=3)  # 발견 완료 후 목록·상세에 남아 있는 기간

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
    found = "발견완료"


router = APIRouter()
_state = {}  # msspsnIdntfccd → {"status", "issued_at", "found_at"} (시연용 변경분)


def _now():
    return datetime.now(KST)


def _enrich(raw):
    """원본 항목에 추가 필드를 붙인다. 원본 딕셔너리는 바꾸지 않는다."""
    sid = raw["msspsnIdntfccd"]
    st = _state.get(sid, {})
    occr = datetime.strptime(raw["occrde"], "%Y%m%d").replace(tzinfo=KST)
    return {
        **raw,
        "occrAdres": (raw.get("occrAdres") or "").strip(),
        "status": st.get("status", Status.searching.value),
        "issued_at": st.get("issued_at", occr).isoformat(),  # 발령 시각이 없으면 발생일 0시
        "found_at": st["found_at"].isoformat() if st.get("found_at") else None,
        "target_label": TARGET_LABELS.get(raw.get("writngTrgetDscd"), "기타"),
        "photo_url": None,
        "source": "자료 출처: 경찰청",
    }


def _expired(st):
    return st.get("found_at") is not None and _now() - st["found_at"] > FOUND_VISIBLE


def _find(sid):
    raws, notice = source.load_alerts()
    raw = next((r for r in raws if r["msspsnIdntfccd"] == sid), None)
    if raw is None:
        raise HTTPException(404, notice or f"경보 {sid}를 찾을 수 없습니다")
    return raw


@router.get("/alerts", tags=["alerts"], summary="경보 목록")
def list_alerts(
    days: int = Query(7, ge=1, description="최근 며칠 안에 발령된 경보만"),
    status: Status | None = Query(None, description="수색중 / 발견완료"),
):
    raws, notice = source.load_alerts()
    since = _now() - timedelta(days=days)
    items = []
    for raw in raws:
        if _expired(_state.get(raw["msspsnIdntfccd"], {})):
            continue
        item = _enrich(raw)
        if datetime.fromisoformat(item["issued_at"]) < since:
            continue
        if status and item["status"] != status.value:
            continue
        items.append(item)
    items.sort(key=lambda x: x["issued_at"], reverse=True)
    return {"notice": notice, "totalCount": len(items), "list": items}


@router.get("/alerts/{sid}", tags=["alerts"], summary="경보 상세")
def get_alert(sid: int):
    raw = _find(sid)
    if _expired(_state.get(sid, {})):
        raise HTTPException(404, f"경보 {sid}는 발견 완료 후 3일이 지나 내려갔습니다")
    return _enrich(raw)


@router.post("/test/fire/{sid}", tags=["test"], summary="시연용: 방금 발령된 새 경보로 만들기")
def test_fire(sid: int):
    _find(sid)
    _state[sid] = {"status": Status.searching.value, "issued_at": _now(), "found_at": None}
    return _enrich(_find(sid))


@router.post("/test/found/{sid}", tags=["test"], summary="시연용: 발견 완료로 바꾸기")
def test_found(sid: int):
    _find(sid)
    _state.setdefault(sid, {}).update(status=Status.found.value, found_at=_now())
    return _enrich(_find(sid))
