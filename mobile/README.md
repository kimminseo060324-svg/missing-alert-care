# 기억해줘 (Flutter 앱)

실종경보 앱의 **뼈대**예요. 피그마 "기억해줘 시안"의 화면 01~07을 옮겼고,
화면끼리 이동되고, 경보는 우리 서버(`backend/`)에서 읽어요.
Firebase 푸시 알림(토픽 구독, 알림을 누르면 상세 화면)이 붙어 있어요.

## 내 컴퓨터에서 실행하기

1. Flutter 설치: https://docs.flutter.dev/get-started/install (Android Studio도 같이 설치).
   팀 버전은 **Flutter 3.41.9 stable (Dart 3.11)** 이에요. `.fvmrc`에 고정돼 있어서
   [fvm](https://fvm.app)을 쓰면 `fvm install`로 같은 버전을 받을 수 있어요. (fvm을 쓰면 아래 `flutter`를 `fvm flutter`로 바꿔 입력)
2. 설치 확인: 터미널에서 `flutter --version`(3.41.9인지) → `flutter doctor` → 빨간 X가 없으면 준비 끝
3. 안드로이드 폰을 USB로 연결하고 "USB 디버깅"을 켜요 (없으면 Android Studio의 에뮬레이터)
4. Firebase 설정 파일 `google-services.json`을 팀에게 받아서 `mobile/android/app/`에 넣어요.
   이 파일이 없으면 빌드가 안 돼요. git에는 올리지 않아요(`.gitignore`에 있어요).
5. 이 폴더에서:

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter run
```

- 시연용 apk 만들기: `flutter build apk` → `build/app/outputs/flutter-apk/app-release.apk`
- 테스트: `flutter test`

## 폴더 구조

```
lib/
  main.dart              앱 시작 (첫 화면 = 시연 메뉴)
  app_routes.dart        화면 이동 모음
  theme/                 색상(app_colors), 글자(app_text), 테마
  models/missing_alert.dart   경보 한 건 (경찰청 API 필드 이름 그대로)
  data/alert_repository.dart  경보 읽기 (우리 서버 / 앱 안 가짜 데이터)
  data/api_settings.dart      서버 주소 설정 (휴대폰에 저장)
  push/                  푸시 알림 (Firebase 연결, 토픽 구독, 알림 눌렀을 때 화면 열기)
  widgets/               공통 부품 (상태 칩, 태그, 버튼, 알림 카드, 옷차림 그림 …)
  screens/               화면 01~07
assets/
  data/missing-alerts.json    시연용 가짜 데이터
  fonts/                 Noto Sans KR (한글·영문만 남긴 가변 글꼴, OFL)
```

| 피그마 | 파일 |
|---|---|
| 01 잠금-접힌 알림 · 02 펼친 알림 · 03 발견 완료 | `screens/lock_screen.dart` |
| 04 경보 목록 | `screens/alert_list_screen.dart` |
| 05 실종 정보 상세 | `screens/alert_detail_screen.dart` |
| 06 목격 제보 | `screens/report_screen.dart` |
| 07 발견 완료 상세 | `screens/found_detail_screen.dart` |

## 데이터 규칙

- 앱은 외부 API(경찰청, 행안부)를 **직접 부르지 않아요**. 나중에 우리 서버만 불러요.
- `assets/data/missing-alerts.json`은 `sample-data/missing-alerts.json`과 같은 필드에
  앱 전용 필드 3개를 더했어요.
  - `clothingTop`(상의), `clothingBottom`(하의·신발): 앱 안 가짜 데이터의 옷차림. 비어 있으면 "정보 없음".
  - 서버 응답에서는 `ai` 필드에서 읽어요 (목록에는 `status`와 `summary`만 와요).
    - 05 상세 인상착의: 상의 = `ai.clothing.upper`, 하의 = `lower`, 신발 = `shoes`, 소지품 = `accessories`를 따로 보여 줘요.
    - 05 상세 "이것만 기억하세요": `ai.summary`(최대 3개)를 칸마다 하나씩. 3개보다 적으면 남은 칸에 키, 요약이 없으면 상의·하의·키.
    - 04 목록 한 줄: `ai.summary`를 " · "로 이어서.
    - `ai.status`가 `pending`이면 "분석 중", `done`인데 결과가 비면 "옷차림 정보 없음", `unavailable`이면 "AI 정보를 제공할 수 없음".
    - 05 상세 "이것만 기억하세요"는 좁은 칸이라 "분석 중" / "제공 불가" / "정보 없음"으로 짧게 써요.
    - 목록에는 `ai.clothing`이 없어서, 서버 모드에서 05 상세를 열면 상세(`/alerts/{id}`)를 바로 다시 읽어요. 읽는 동안 "불러오는 중", 실패하면 "옷차림을 불러오지 못했어요" + "다시 시도". 시연 메뉴의 잠금화면 카드·목격 제보도 열기 전에 상세를 읽어요.
    - 상세 화면을 아래로 당기면 서버에서 다시 읽어요. "분석 중"일 때는 "새로고침" 버튼도 보여요. 여러 번 당겨도 마지막 요청의 응답만 화면에 넣어요.
    - `ai`가 없거나 `null`이면(앱 안 가짜 데이터) 예전처럼 상의, 하의·신발 2칸이에요.
  - `demoFoundTime`: 시연용. 값이 있으면 "발견 완료"로 보여요.
- 경찰청 사진은 쓰지 않고, 얼굴 없는 옷차림 그림만 보여줘요 (지금은 옷 색으로 그린 임시 그림).
- 출처 문구: "자료 출처: 경찰청 · 행안부 재난문자"

## 아직 안 한 것

- 182 전화 연결 (지금은 안내 메시지만 떠요), 지도, AI가 그린 옷차림 이미지 (지금 그림은 옷 글자의 색으로 그려요)

## 서버 연결

앱은 우리 서버의 `GET /alerts`(목록)와 `GET /alerts/{id}`(상세)만 불러요. 경찰청·행안부 API는 부르지 않아요.

1. 서버 켜기 (backend 폴더): `uvicorn main:app --reload --host 0.0.0.0 --port 8000`
   - `--host 0.0.0.0`이 있어야 휴대폰에서 접속할 수 있어요.
2. 앱의 시연 메뉴 오른쪽 위 **서버 주소**에서 주소를 넣고 "연결 확인" → "저장"
   - 에뮬레이터: `http://10.0.2.2:8000` (기본값)
   - 휴대폰: 컴퓨터와 같은 와이파이에서 컴퓨터 IP, 예: `http://192.168.0.5:8000`
     (맥 IP 확인: `ipconfig getifaddr en0`)
   - 빌드할 때 기본 주소 바꾸기: `fvm flutter run --dart-define=API_BASE_URL=http://192.168.0.5:8000`
3. 서버 없이 시연할 때는 같은 화면에서 **앱 안 가짜 데이터로 보기**를 켜요.
   앱 안 데이터에는 경보 종료 예시(9990007)가 들어 있어요.

상태 표시: 서버 응답의 `status`를 그대로 따라요.
- `수색중` → "수색 중" 남색 라벨, 05 상세
- `경보종료` → "경보 종료" 회색 라벨, 05 상세 위에 "경보가 종료됐어요" 안내 (수색 중 건수에서 빠져요)
- `발견완료` → "발견 완료 (시각)" 초록 라벨, 07 발견 완료 상세

가상 데이터 모드 서버는 처음에 모두 수색 중이에요. 발견 완료 화면을 보려면 서버의
`POST /test/found/{id}`를 부르면 돼요 (http://localhost:8000/docs 에서 누를 수 있어요).

## 푸시 알림

- 토픽 `missing_alerts_osan`을 구독해요. 알림 채널 id는 `missing_alerts`예요 (`MainActivity.kt`에서 만들어요).
- 서버가 보내는 data: `type`(`missing_alert`), `event`(`issued`/`closed`), `alert_id`(경찰청 식별번호), `status`, `region`, `version`, `lat`/`lng`(있을 때만). 값은 전부 문자열이에요.
- 앱을 보고 있을 때 온 푸시는 Android가 띄우지 않아서 앱이 같은 채널로 직접 띄워요(`flutter_local_notifications`). 백그라운드이거나 꺼져 있을 때는 Android가 띄우고 앱은 띄우지 않아서 두 번 뜨지 않아요.
- 같은 경보의 알림은 tag `alert_{alert_id}`가 같아요. 경보 종료·발견 완료 알림이 오면 앞의 "찾고 있어요" 알림을 바꿔치기해요. 백그라운드에서도 바꿔치기되려면 서버가 같은 tag를 넣어 보내야 해요.
- 알림을 누르면 `alert_id`로 서버에서 그 경보의 최신 정보(`GET /alerts/{id}`)를 받아 05 상세(발견 완료면 07)를 열고, 서버에 없으면(404) 04 목록을 열어요.
- 확인: Firebase 콘솔 → Messaging → 새 캠페인 → 알림 → 대상을 주제 `missing_alerts_osan`으로, 추가 옵션의 맞춤 데이터에 `type`=`missing_alert`, `alert_id`=`9990001`을 넣고 보내요.
