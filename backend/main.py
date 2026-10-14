"""Missing Alert Care 백엔드 서버.

실행 (backend 폴더에서): uvicorn main:app --reload --host 0.0.0.0 --port 8000
.env의 DATA_SOURCE=safe182이면 서버가 켜질 때 안전Dream 주기 조회를 시작한다.
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import alerts
from services import sync
from services.data_source import source


@asynccontextmanager
async def lifespan(app):
    shutdown = None if source.IS_SAMPLE else sync.start()
    yield
    if shutdown:
        shutdown()


app = FastAPI(title="Missing Alert Care API", lifespan=lifespan)

# 앱·웹에서 부를 수 있게 모든 출처 허용 (개발용, 배포 전 실제 주소로 좁힐 것)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

app.include_router(alerts.router)
