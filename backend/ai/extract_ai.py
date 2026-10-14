"""Gemini로 옷차림 추출 (google-genai, JSON Schema 구조화 출력, temperature 0).

- 키는 저장소 루트 .env의 GEMINI_API_KEY에서만 읽고 출력하지 않는다. 모델은 GEMINI_MODEL로 바꿀 수 있다.
- AI에는 개인정보(이름·번호·상세 주소)를 지운 문장(preprocess.redact)만 보낸다.
- 실종 문자인지(is_missing_alert)도 함께 판단하게 한다.
- 항목마다 근거 문구(evidence)를 받아, 원문에 실제로 있는 것만 남긴다 (schema.verify_ai_response).
- 요청마다 타임아웃을 건다 (.env GEMINI_TIMEOUT_SEC, 기본 30초). google-genai의 HttpOptions.timeout은
  밀리초 단위 정수다 (SDK 문서: "timeout: int | None — Timeout for the request in milliseconds").
  SDK는 retry_options를 주지 않으면 스스로 다시 부르지 않으므로, 재시도는 여기서만 한다.
- 타임아웃, HTTP 429(분당 호출 제한)·500·503은 15초 → 30초 → 60초 기다렸다가 다시 부르고(최대 3번),
  그래도 안 되면 멈춘다. 그 밖의 오류는 다시 부르지 않는다.
- 오류가 나도 키, 요청 내용, 응답 본문은 메시지·로그에 넣지 않는다.
"""
import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv

from .preprocess import redact
from .schema import AI_RESPONSE_SCHEMA, STANDARD_COLORS, verify_ai_response

ENV_PATH = Path(__file__).resolve().parents[2] / ".env"
DEFAULT_MODEL = "gemini-3.5-flash-lite"  # 안정(Stable) Flash-Lite, 구조화 출력 지원 (2026-07 업데이트)
RETRY_WAITS = (15, 30, 60)  # 다시 부르기 전 기다리는 초 (최대 3번)
RETRY_HTTP_CODES = {429, 500, 503}
DEFAULT_CALL_INTERVAL = 4.0  # 호출 사이 쉬는 초 (GEMINI_CALL_INTERVAL_SEC)
DEFAULT_TIMEOUT = 30.0  # 요청 하나의 제한 시간(초) (GEMINI_TIMEOUT_SEC)

PROMPT = """너는 재난문자를 읽고 실종자 찾기 문자인지 판단한 뒤, 인상착의(옷차림)를 JSON으로 정리한다.

규칙
0. is_missing_alert: 실종자를 찾는 문자이면 true. "실종", "찾습니다"라는 말이 없어도 사람이 돌아오지 않았거나 연락이 끊겨
   찾고 있는 내용이면 true. 날씨·교통·화재·단수 같은 안내는 false이고, 이때 나머지는 모두 비운다.
1. 아래 [문자]에 실제로 적힌 내용만 쓴다. 적혀 있지 않은 옷·색·소지품은 절대 만들지 말고 빈 값("" 또는 [])으로 둔다.
2. 모든 항목의 evidence에는 [문자]에서 그 근거가 되는 부분을 글자 그대로(띄어쓰기 포함) 옮겨 적는다.
3. upper=상의, lower=하의, shoes=신발. 원피스·작업복·잠옷·체육복처럼 위아래가 한 벌인 옷은 upper에 넣고 lower는 비운다.
   단, 상의와 하의를 같은 옷으로 위아래 함께 입었다고 적혀 있으면 upper와 lower에 각각 넣는다.
4. accessories: 모자, 안경, 가방, 지팡이처럼 몸에 쓰거나 지니고 있는 것.
5. negatives: "모자미착용"처럼 착용하지 않았다고 적힌 것의 종류(예: "모자"). "맨발"이면 "신발".
   착용하지 않은 것은 accessories나 옷 칸에 넣지 않는다.
6. color는 다음 중 하나로만 쓴다: {colors}. 곤색·네이비·남색은 "남색", 청색은 "청색"(남색과 다른 색)이다.
   표에 없는 색은 가장 가까운 색으로 쓴다. 색이 없으면 "".
7. type에는 옷 이름만 쓴다(예: "체크남방", "꽃무늬 블라우스", "청바지"). 색은 type에 넣지 않는다.
   오타나 줄임말은 표준 옷 이름으로 고쳐 쓴다.
8. 띄어쓰기 없이 붙여 쓴 표현("청색체크남방검정면바지")도 나눠서 읽는다.
9. summary: 길에서 이 사람을 알아보기 쉬운 옷·소지품 특징 3개 이하. 드물고 눈에 띄는 것을 먼저 쓴다
   (예: 형광 조끼, 노란 장화, 캐리어). 나이·성별·키·몸무게·머리 모양은 넣지 않는다. 옷·소지품 정보가 없으면 비운다.

[문자]
{text}
"""


class AIError(Exception):
    """사람이 읽을 안내 문구만 담는다 (키·요청·응답 본문 없음)."""


def model_name():
    return (os.getenv("GEMINI_MODEL") or DEFAULT_MODEL).strip()


def _env_seconds(name, default, low, high):
    """.env 값을 초로 읽는다. 비었거나 숫자가 아니거나 범위 밖이면 기본값."""
    try:
        sec = float((os.getenv(name) or "").strip())
    except ValueError:
        return default
    return sec if low <= sec <= high else default


def call_interval():
    """GEMINI_CALL_INTERVAL_SEC (호출 사이 쉬는 초, 0~600). 아니면 기본 4초."""
    return _env_seconds("GEMINI_CALL_INTERVAL_SEC", DEFAULT_CALL_INTERVAL, 0, 600)


def timeout_sec():
    """GEMINI_TIMEOUT_SEC (요청 하나의 제한 시간, 1~600초). 아니면 기본 30초."""
    return _env_seconds("GEMINI_TIMEOUT_SEC", DEFAULT_TIMEOUT, 1, 600)


def get_client():
    """키를 읽어 클라이언트를 만든다. 키가 없으면 안내 문구로 끝낸다. 타임아웃은 밀리초로 넘긴다."""
    load_dotenv(ENV_PATH)
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise SystemExit("[오류] GEMINI_API_KEY가 없습니다. 저장소 루트의 .env에 키를 넣은 뒤 --mode ai를 실행해 주세요.")
    from google import genai  # 키가 있을 때만 불러온다
    from google.genai import types
    return genai.Client(api_key=key, http_options=types.HttpOptions(timeout=int(timeout_sec() * 1000)))


def build_prompt(text):
    return PROMPT.format(colors=", ".join(STANDARD_COLORS), text=text)


def _timeout_errors():
    """SDK가 쓰는 HTTP 라이브러리(httpx, 있으면 httpx2)의 타임아웃 예외."""
    import httpx
    errs = [httpx.TimeoutException]
    try:
        import httpx2
        errs.append(httpx2.TimeoutException)
    except ImportError:
        pass
    return tuple(errs)


def _generate(client, prompt, config, sleep, log):
    """한 번 호출. 타임아웃·429·500·503이면 RETRY_WAITS만큼 기다렸다 다시 부른다 (최대 3번)."""
    from google.genai import errors

    timeouts = _timeout_errors()
    for attempt in range(len(RETRY_WAITS) + 1):
        try:
            return client.models.generate_content(model=model_name(), contents=prompt, config=config)
        except errors.APIError as e:
            # e의 문자열에는 응답 본문이 담길 수 있어 상태 코드만 쓴다
            label, reason, retryable = str(e.code), f"HTTP {e.code}", e.code in RETRY_HTTP_CODES
        except timeouts:
            label = reason = f"응답 시간 초과({timeout_sec():g}초)"
            retryable = True
        except Exception as e:  # 예외 메시지에 요청 정보가 담길 수 있어 종류만 쓴다
            raise AIError(f"Gemini 호출에 실패했습니다 ({type(e).__name__})") from None
        if retryable and attempt < len(RETRY_WAITS):
            wait = RETRY_WAITS[attempt]
            log(f"{label}, {wait}초 후 재시도 ({attempt + 1}/{len(RETRY_WAITS)})")
            sleep(wait)
            continue
        suffix = f", {len(RETRY_WAITS)}번 재시도 후" if retryable else ""
        raise AIError(f"Gemini API 오류 ({reason}{suffix})") from None


def call(client, raw_text, sleep=time.sleep, log=print):
    """원문 하나 → AI 원래 응답(검증 전 dict). 캐시에 저장해 두면 검증 규칙을 바꿔도 다시 부르지 않고 다시 채점할 수 있다.
    응답에는 근거 문구(개인정보를 지운 문장의 일부)가 들어 있다."""
    from google.genai import types

    config = types.GenerateContentConfig(
        temperature=0,
        response_mime_type="application/json",
        response_json_schema=AI_RESPONSE_SCHEMA,
    )
    resp = _generate(client, build_prompt(redact(raw_text)), config, sleep, log)
    try:
        data = json.loads(resp.text or "")
    except ValueError:
        raise AIError("Gemini 응답이 JSON이 아닙니다") from None
    if not isinstance(data, dict):
        raise AIError("Gemini 응답이 객체(JSON object)가 아닙니다")
    return data


def verify(data, raw_text, lenient=True, stats=None):
    """AI 원래 응답 → (출력 형식, 버린 항목·색 수, 실종 문자인지). 형식이 틀린 항목 수는 stats["invalid"]에."""
    out, dropped = verify_ai_response(data, redact(raw_text), lenient=lenient, stats=stats)
    return out, dropped, isinstance(data, dict) and data.get("is_missing_alert") is True


def extract(client, raw_text, sleep=time.sleep, log=print):
    """원문 하나 → (출력 형식, 버린 항목·색 수, 실종 문자인지). call + verify."""
    return verify(call(client, raw_text, sleep, log), raw_text)
