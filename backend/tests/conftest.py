"""테스트 공통 설정. 저장소 루트에서 `pytest backend`로 실행한다."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # backend 폴더 (main, routers, services)

from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402
from routers import alerts  # noqa: E402


@pytest.fixture(autouse=True)
def reset_state():
    """시연용 상태(발령·발견)는 메모리에 남으므로 테스트마다 비운다."""
    alerts._state.clear()
    yield
    alerts._state.clear()


@pytest.fixture
def client():
    return TestClient(app)
