"""테스트 공통 설정. 저장소 루트에서 `pytest backend`로 실행한다."""
import os
import sys
from pathlib import Path

# 테스트는 가상 데이터 기준이다. .env나 환경변수가 safe182여도 앱을 불러오기 전에 sample로 고정한다
# (load_dotenv는 이미 있는 환경변수를 덮어쓰지 않으므로 이 값이 유지된다)
os.environ["DATA_SOURCE"] = "sample"
os.environ["FIREBASE_SERVICE_ACCOUNT_PATH"] = ""  # 테스트에서 실제 푸시를 보내지 않게 끈다

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
