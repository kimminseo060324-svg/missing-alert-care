"""가상 실종경보 데이터 읽기.

나중에 실제 안전Dream API로 바꿀 때는 SOURCE, IS_SAMPLE과 load_alerts()(원본 목록, 안내 문구)를
같은 모양으로 갖춘 모듈을 만들고 routers/alerts.py의 import만 바꾸면 된다.
(실제 모듈은 SOURCE = "자료 출처: 경찰청", IS_SAMPLE = False)
"""
import json
from pathlib import Path

SOURCE = "시연용 가상 데이터"  # 응답의 source 필드
IS_SAMPLE = True               # 응답의 is_sample 필드
SAMPLE_PATH = Path(__file__).resolve().parents[2] / "sample-data" / "missing-alerts.json"


def load_alerts():
    """(안전Dream 응답의 list 항목들, 안내 문구 또는 None)을 돌려준다. 파일이 없어도 예외를 내지 않는다."""
    if not SAMPLE_PATH.exists():
        return [], f"가상 데이터 파일이 없습니다: {SAMPLE_PATH.relative_to(SAMPLE_PATH.parents[1])}"
    try:
        data = json.loads(SAMPLE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [], f"가상 데이터 파일을 읽지 못했습니다: {e}"
    return data.get("list") or [], None
