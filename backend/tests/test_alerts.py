"""실종경보 API 테스트. 가상 데이터만 쓰고 외부 API는 부르지 않는다."""
from datetime import datetime, timedelta

import pytest

from routers import alerts

FIXED_NOW = datetime(2026, 10, 8, 12, 0, tzinfo=alerts.KST)
SAMPLE_COUNT = 6  # sample-data/missing-alerts.json


def _row(sid, occrde="__missing__"):
    row = {"msspsnIdntfccd": sid, "nm": "테스트", "writngTrgetDscd": "070", "occrAdres": "가상구 "}
    if occrde != "__missing__":
        row["occrde"] = occrde
    return row


@pytest.fixture
def fixed_now(monkeypatch):
    monkeypatch.setattr(alerts, "_now", lambda: FIXED_NOW)


@pytest.fixture
def fake_rows(monkeypatch):
    """가상 데이터 대신 쓸 목록을 넣는다."""
    def use(rows):
        monkeypatch.setattr(alerts.source, "load_alerts", lambda: (rows, None))
    return use


def _ids(res):
    return [x["msspsnIdntfccd"] for x in res.json()["list"]]


# 목록 기본값 ---------------------------------------------------------------

def test_list_without_days_returns_all_sample_alerts(client):
    res = client.get("/alerts")
    assert res.status_code == 200
    body = res.json()
    assert body["is_sample"] is True
    assert body["totalCount"] == SAMPLE_COUNT > 0
    assert len(body["list"]) == SAMPLE_COUNT


def test_list_without_days_is_not_empty_long_after_sample_dates(client, monkeypatch):
    monkeypatch.setattr(alerts, "_now", lambda: datetime(2030, 1, 1, tzinfo=alerts.KST))
    assert client.get("/alerts").json()["totalCount"] == SAMPLE_COUNT


# days 날짜 필터 -------------------------------------------------------------

def test_days_filters_by_issued_date(client, fixed_now, fake_rows):
    fake_rows([_row(1, "20261007"), _row(2, "20261002"), _row(3, "20260901")])
    assert _ids(client.get("/alerts", params={"days": 7})) == [1, 2]
    assert _ids(client.get("/alerts", params={"days": 3})) == [1]
    assert _ids(client.get("/alerts")) == [1, 2, 3]
    assert _ids(client.get("/alerts", params={"days": 36500})) == [1, 2, 3]  # 최대값


@pytest.mark.parametrize("days", ["0", "-1", "abc", "1.5", "36501", "999999999"])
def test_invalid_days_is_422(client, days):
    assert client.get("/alerts", params={"days": days}).status_code == 422


# 잘못된 발생일(occrde) -------------------------------------------------------

BAD_OCCRDE = [
    _row(11),                  # 누락
    _row(12, None),            # null
    _row(13, "2026101"),       # 7자리
    _row(14, "202610011"),     # 9자리
    _row(15, "20260230"),      # 없는 날짜
    _row(16, "2026-10-01"),    # 다른 형식
]


def test_bad_occrde_does_not_break_list(client, fixed_now, fake_rows):
    fake_rows([*BAD_OCCRDE, _row(1, "20261007")])
    res = client.get("/alerts")
    assert res.status_code == 200
    ids = _ids(res)
    assert ids[0] == 1  # 날짜를 아는 경보가 앞, 모르는 경보는 뒤
    assert sorted(ids[1:]) == [11, 12, 13, 14, 15, 16]
    assert all(x["issued_at"] is None for x in res.json()["list"][1:])


def test_bad_occrde_is_excluded_when_filtering_by_days(client, fixed_now, fake_rows):
    fake_rows([*BAD_OCCRDE, _row(1, "20261007")])
    res = client.get("/alerts", params={"days": 7})
    assert res.status_code == 200
    assert _ids(res) == [1]


@pytest.mark.parametrize("row", BAD_OCCRDE, ids=lambda r: str(r["msspsnIdntfccd"]))
def test_bad_occrde_detail_is_200(client, fake_rows, row):
    fake_rows([row])
    res = client.get(f"/alerts/{row['msspsnIdntfccd']}")
    assert res.status_code == 200
    assert res.json()["issued_at"] is None


def test_fire_gives_bad_occrde_alert_a_date(client, fake_rows):
    fake_rows([_row(11)])
    client.post("/test/fire/11")
    assert _ids(client.get("/alerts", params={"days": 7})) == [11]


@pytest.mark.parametrize(
    ("value", "ok"),
    [("20261001", True), (20261001, True), (" 20261001 ", True),
     (None, False), ("", False), ("2026101", False), ("20260230", False), ("2026100a", False)],
)
def test_parse_occrde(value, ok):
    assert (alerts._parse_occrde(value) is not None) is ok


# 상세 -------------------------------------------------------------------

def test_detail_ok(client):
    res = client.get("/alerts/9990001")
    assert res.status_code == 200
    body = res.json()
    assert body["msspsnIdntfccd"] == 9990001
    assert body["status"] == "수색중"
    assert body["is_sample"] is True


def test_detail_not_found(client):
    assert client.get("/alerts/1234").status_code == 404


# 시연용 엔드포인트 -------------------------------------------------------------

def test_fire_moves_alert_into_recent_list_first(client):
    res = client.post("/test/fire/9990001")
    assert res.status_code == 200
    issued = datetime.fromisoformat(res.json()["issued_at"])
    assert abs(alerts._now() - issued) < timedelta(minutes=1)

    ids = _ids(client.get("/alerts", params={"days": 7}))
    assert ids[0] == 9990001
    assert _ids(client.get("/alerts"))[0] == 9990001


def test_fire_unknown_is_404(client):
    assert client.post("/test/fire/1234").status_code == 404


def test_found_marks_alert_found(client):
    res = client.post("/test/found/9990003")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "발견완료"
    assert body["found_at"] is not None

    found = client.get("/alerts", params={"status": "발견완료"}).json()
    assert [x["msspsnIdntfccd"] for x in found["list"]] == [9990003]
    searching = client.get("/alerts", params={"status": "수색중"}).json()
    assert 9990003 not in [x["msspsnIdntfccd"] for x in searching["list"]]


def test_found_unknown_is_404(client):
    assert client.post("/test/found/1234").status_code == 404


def test_found_alert_hidden_after_three_days(client, monkeypatch):
    client.post("/test/found/9990003")
    later = alerts._now() + timedelta(days=3, minutes=1)
    monkeypatch.setattr(alerts, "_now", lambda: later)

    assert 9990003 not in _ids(client.get("/alerts"))
    assert client.get("/alerts").json()["totalCount"] == SAMPLE_COUNT - 1
    assert client.get("/alerts/9990003").status_code == 404


def test_found_alert_still_visible_within_three_days(client, monkeypatch):
    client.post("/test/found/9990003")
    later = alerts._now() + timedelta(days=2)
    monkeypatch.setattr(alerts, "_now", lambda: later)

    assert 9990003 in _ids(client.get("/alerts"))
    assert client.get("/alerts/9990003").status_code == 200


def test_state_is_reset_between_tests(client):
    assert alerts._state == {}
    assert all(x["status"] == "수색중" for x in client.get("/alerts").json()["list"])
