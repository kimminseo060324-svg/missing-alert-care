"""안전Dream API 응답 처리(services/safe182.py) 테스트. requests.post를 가짜로 바꿔 네트워크 없이 돈다."""
import json

import pytest
import requests

from services import safe182

FAKE_KEY = "fake-key-should-never-be-printed"
FAKE_ID = "fake-id-should-never-be-printed"


def _response(status=200, body=None, raw=None):
    r = requests.models.Response()
    r.status_code = status
    r._content = raw if raw is not None else json.dumps(body).encode()
    r.headers["content-type"] = "application/json" if raw is None else "text/html"
    return r


@pytest.fixture
def fake_post(monkeypatch):
    """page 번호별 응답을 넣는다. 받은 요청 수를 센다."""
    calls = []

    def use(pages):
        def post(url, data, timeout):
            calls.append(data["page"])
            p = pages[data["page"]] if isinstance(pages, dict) else pages
            return p() if callable(p) else p
        monkeypatch.setattr(safe182.requests, "post", post)
        return calls
    return use


def _ok(total, rows):
    return _response(body={"result": "00", "msg": "OK", "totalCount": total, "list": rows})


def _fetch():
    counted = []
    rows, received, total, skipped = safe182.fetch_all(FAKE_ID, FAKE_KEY, lambda: counted.append(1))
    return rows, received, total, skipped, len(counted)


def test_string_ids_are_normalized_to_int(fake_post):
    fake_post({1: _ok(2, [{"msspsnIdntfccd": "9990005"}, {"msspsnIdntfccd": " 0009990006 "}])})
    rows, received, total, skipped, _ = _fetch()
    assert [r["msspsnIdntfccd"] for r in rows] == [9990005, 9990006]
    assert (received, total, skipped) == (2, 2, 0)


def test_non_items_and_missing_ids_are_skipped_and_counted(fake_post):
    fake_post({1: _ok(5, ["항목 아님", {"nm": "테스트"}, {"msspsnIdntfccd": None},
                         {"msspsnIdntfccd": "abc"}, {"msspsnIdntfccd": 1}])})
    rows, received, total, skipped, _ = _fetch()
    assert [r["msspsnIdntfccd"] for r in rows] == [1]
    assert (received, total, skipped) == (5, 5, 4)


def test_reads_all_pages_and_counts_each_call(fake_post):
    page1 = [{"msspsnIdntfccd": i} for i in range(1, 101)]
    page2 = [{"msspsnIdntfccd": i} for i in range(101, 113)]
    calls = fake_post({1: _ok(112, page1), 2: _ok(112, page2)})
    rows, received, total, _, counted = _fetch()
    assert len(rows) == received == total == 112
    assert calls == [1, 2] and counted == 2


def test_duplicate_ids_keep_first(fake_post):
    fake_post({1: _ok(2, [{"msspsnIdntfccd": 7, "nm": "첫번째"}, {"msspsnIdntfccd": "7", "nm": "두번째"}])})
    rows, received, *_ = _fetch()
    assert [r["nm"] for r in rows] == ["첫번째"] and received == 2


def test_result_code_80_raises_daily_limit(fake_post):
    fake_post({1: _response(body={"result": "80", "msg": "한도 초과"})})
    with pytest.raises(safe182.DailyLimitExceeded):
        _fetch()


@pytest.mark.parametrize(
    ("response", "expected"),
    [
        (_response(500, {"x": 1}), "HTTP 500"),
        (_response(raw=b"<html>error</html>"), "JSON이 아닙니다"),
        (_response(body={"msg": "result 없음"}), "result가 없습니다"),
        (_response(body={"result": "99", "msg": "응답 본문 문구"}), "결과 코드 99"),
        (_response(body={"result": "00"}), "totalCount"),
        (_response(body={"result": "00", "totalCount": 1, "list": "목록 아님"}), "목록이 아닙니다"),
    ],
)
def test_bad_responses_raise_readable_error_without_body(fake_post, response, expected):
    fake_post(lambda: response)
    with pytest.raises(safe182.Safe182Error) as e:
        _fetch()
    assert expected in str(e.value)
    assert "응답 본문 문구" not in str(e.value) and "<html>" not in str(e.value)


def test_request_failure_hides_key_and_url(monkeypatch):
    def post(url, data, timeout):  # requests 예외 메시지에는 URL과 요청 값이 들어갈 수 있다
        raise requests.ConnectionError(f"{url}?esntlId={data['esntlId']}&authKey={data['authKey']}")
    monkeypatch.setattr(safe182.requests, "post", post)
    with pytest.raises(safe182.Safe182Error) as e:
        _fetch()
    msg = str(e.value)
    assert "요청에 실패했습니다" in msg
    assert FAKE_KEY not in msg and FAKE_ID not in msg and "safe182.go.kr" not in msg
    assert e.value.__cause__ is None and e.value.__suppress_context__  # 원래 예외가 traceback에 붙지 않음


@pytest.mark.parametrize(("value", "expected"), [
    (5, 5), ("5", 5), (" 0009990006 ", 9990006), ("", None), ("12a", None), (None, None), (True, None), (1.5, None),
])
def test_normalize_id(value, expected):
    assert safe182.normalize_id(value) == expected
