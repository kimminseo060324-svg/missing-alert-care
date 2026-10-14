"""데이터 모드 선택. .env의 DATA_SOURCE: sample(기본값) = 가상 데이터, safe182 = 실제 안전Dream."""
import os
from pathlib import Path

from dotenv import load_dotenv

from services import safe182, sample_data

load_dotenv(Path(__file__).resolve().parents[2] / ".env")  # 저장소 루트의 .env

MODE = (os.getenv("DATA_SOURCE") or "sample").strip().lower()
MODULES = {"sample": sample_data, "safe182": safe182}
if MODE not in MODULES:
    raise RuntimeError(f"DATA_SOURCE는 sample 또는 safe182여야 합니다 (현재 값: {MODE!r})")
source = MODULES[MODE]
