"""Gemini로 옷차림 추출 (google-genai, JSON Schema 구조화 출력, temperature 0).

- 키는 저장소 루트 .env의 GEMINI_API_KEY에서만 읽고 출력하지 않는다. 모델은 GEMINI_MODEL로 바꿀 수 있다.
- AI에는 개인정보를 뺀 인상착의 부분(preprocess.clothing_part)만 보낸다.
- 항목마다 근거 문구(evidence)를 받아, 원문에 실제로 있는 것만 남긴다 (schema.verify_ai_response).
- 오류가 나도 키, 요청 내용, 응답 본문은 메시지에 넣지 않는다.
"""
import json
import os
from pathlib import Path

from dotenv import load_dotenv

from .preprocess import clothing_part
from .schema import AI_RESPONSE_SCHEMA, STANDARD_COLORS, verify_ai_response

ENV_PATH = Path(__file__).resolve().parents[2] / ".env"
DEFAULT_MODEL = "gemini-3.5-flash-lite"  # 안정(Stable) Flash-Lite, 구조화 출력 지원 (2026-07 업데이트)

PROMPT = """너는 실종자 찾기 문자에서 인상착의(옷차림)만 뽑아 JSON으로 정리한다.

규칙
1. 아래 [문자]에 실제로 적힌 내용만 쓴다. 적혀 있지 않은 옷·색·소지품은 절대 만들지 말고 빈 값("" 또는 [])으로 둔다.
2. 모든 항목의 evidence에는 [문자]에서 그 근거가 되는 부분을 글자 그대로(띄어쓰기 포함) 옮겨 적는다.
3. upper=상의, lower=하의, shoes=신발. 원피스·작업복·잠옷·체육복처럼 위아래가 한 벌인 옷은 upper에 넣고 lower는 비운다.
4. accessories: 모자, 안경, 가방, 백팩, 지팡이, 보행보조기, 휠체어처럼 몸에 지니거나 쓰는 것.
5. negatives: "모자미착용", "안경 미착용"처럼 착용하지 않았다고 적힌 것의 종류(예: "모자"). "맨발"이면 "신발".
   착용하지 않은 것은 accessories나 옷 칸에 넣지 않는다.
6. color는 다음 중 하나로만 쓴다: {colors}. 곤색·네이비·남색은 "남색", 청색은 "청색"(남색과 다른 색)이다. 색이 없으면 "".
7. type에는 옷 이름만 쓴다(예: "체크남방", "꽃무늬 블라우스", "청바지"). 색은 type에 넣지 않는다.
8. 띄어쓰기 없이 붙여 쓴 표현("청색체크남방검정면바지")도 나눠서 읽는다.
9. summary: 길에서 이 사람을 알아보기 쉬운 특징 3개 이하. 흔한 것보다 드문 것(보조기구, 무늬, 눈에 띄는 색)을 먼저. 옷차림 외 특징(머리 모양 등)도 문자에 있으면 쓸 수 있다.

[문자]
{text}
"""


class AIError(Exception):
    """사람이 읽을 안내 문구만 담는다 (키·요청·응답 본문 없음)."""


def model_name():
    return (os.getenv("GEMINI_MODEL") or DEFAULT_MODEL).strip()


def get_client():
    """키를 읽어 클라이언트를 만든다. 키가 없으면 안내 문구로 끝낸다."""
    load_dotenv(ENV_PATH)
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise SystemExit("[오류] GEMINI_API_KEY가 없습니다. 저장소 루트의 .env에 키를 넣은 뒤 --mode ai를 실행해 주세요.")
    from google import genai  # 키가 있을 때만 불러온다
    return genai.Client(api_key=key)


def build_prompt(text):
    return PROMPT.format(colors=", ".join(STANDARD_COLORS), text=text)


def extract(client, raw_text):
    """원문 하나 → (출력 형식, 근거가 없어 버린 항목 수)."""
    from google.genai import errors, types

    text = clothing_part(raw_text)
    config = types.GenerateContentConfig(
        temperature=0,
        response_mime_type="application/json",
        response_json_schema=AI_RESPONSE_SCHEMA,
    )
    try:
        resp = client.models.generate_content(model=model_name(), contents=build_prompt(text), config=config)
    except errors.APIError as e:
        # e의 문자열에는 응답 본문이 담길 수 있어 상태 코드만 쓴다
        raise AIError(f"Gemini API 오류 (HTTP {e.code})") from None
    except Exception as e:
        raise AIError(f"Gemini 호출에 실패했습니다 ({type(e).__name__})") from None
    try:
        data = json.loads(resp.text or "")
    except ValueError:
        raise AIError("Gemini 응답이 JSON이 아닙니다") from None
    if not isinstance(data, dict):
        raise AIError("Gemini 응답이 객체(JSON object)가 아닙니다")
    return verify_ai_response(data, text)
