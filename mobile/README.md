# 기억해줘 (Flutter 앱)

실종경보 앱의 **뼈대**예요. 피그마 "기억해줘 시안"의 화면 01~07을 옮겼고,
화면끼리 이동만 돼요. 푸시 알림과 서버 연결은 다음 단계에서 붙여요.

## 내 컴퓨터에서 실행하기

1. Flutter 설치: https://docs.flutter.dev/get-started/install (Android Studio도 같이 설치). Flutter 3.27 이상이 필요해요.
2. 설치 확인: 터미널에서 `flutter doctor` → 빨간 X가 없으면 준비 끝
3. 안드로이드 폰을 USB로 연결하고 "USB 디버깅"을 켜요 (없으면 Android Studio의 에뮬레이터)
4. 이 폴더에서:

```bash
cd mobile
flutter pub get
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
  data/alert_repository.dart  가짜 데이터 읽기
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
  - `clothingTop`(상의), `clothingBottom`(하의·신발): 행안부 재난문자에서 AI가 뽑을 값. 비어 있으면 "정보 없음".
  - `demoFoundTime`: 시연용. 값이 있으면 "발견 완료"로 보여요.
- 경찰청 사진은 쓰지 않고, 얼굴 없는 옷차림 그림만 보여줘요 (지금은 옷 색으로 그린 임시 그림).
- 출처 문구: "자료 출처: 경찰청 · 행안부 재난문자"

## 아직 안 한 것

- 182 전화 연결 (지금은 안내 메시지만 떠요), 지도, 푸시 알림, 서버 연결, AI 옷차림 그림
