# adaptive_alarm (Flutter 앱)

습관화 과학 기반 적응형 알람의 Flutter 구현. 핵심 로직(`lib/core/`)은 상위
`../core/` Python 시스템을 **1:1 포팅**한 것이며, 골든 테스트로 parity를 맞춘다.

## 구조

```
lib/
  core/        ★ Python core/ 의 Dart 포팅 (순수 로직, 온디바이스에서 동작)
    config · models · scoring · trend · decision · events · engine
  data/
    sound_catalog.dart   음원 카탈로그 + 음원별 모집단 기준선
  services/
    storage.dart         shared_preferences에 엔진 상태 JSON 영속화
    alarm_scheduler.dart  OS 정밀 알람 + 풀스크린 알림 (기기 의존 ⚠️)
    alarm_controller.dart 세션↔엔진↔저장소 통합 (onRing/onSnooze/onDismiss)
  ui/
    home_screen.dart      알람 시각 설정, 현재 음원/추세, "지금 울리기(테스트)"
    ring_screen.dart      울림 화면, 스누즈/끄기 → 기록 처리
    swap_proposal_sheet.dart  교체 제안 시트(수락/거절)
test/
  core_test.dart   단위 + 골든(parity) 테스트. Python tests/test_core.py와 같은 기대값
```

## 데이터 흐름

```
알람 울림 → RingScreen → AlarmController.onRing/onSnooze/onDismiss
  → core/events.buildRecord (활성 상호작용 시간만, 스누즈 대기 제외)
  → core/engine.recordAlarm → SwapProposal
  → (제안 시) swap_proposal_sheet → acceptSwap / declineSwap
  → storage.saveEngine (JSON)  ← 다음 실행 때 loadEngine으로 복원
```

`engine.toJson()`의 JSON 키는 Python 쪽과 동일(snake_case)이라 저장 데이터가 호환된다.

## 실행 / 검증

```bash
flutter pub get
flutter test          # core 포팅 parity 검증 (Python 골든값과 일치하는지)
flutter run           # 실기기/에뮬레이터

# Flutter 없이 core 로직만 검증 (Dart SDK만 있으면 됨):
dart run tool/core_check.dart   # 22개 골든 체크, Python과 동일 값 확인
```

> **검증됨**: `lib/core/`는 순수 Dart(Flutter 무관)라 Dart SDK만으로 실행·검증된다.
> Python과 동일 시나리오에서 교체 제안일·EWMA가 부동소수점 끝자리까지 일치함을 확인했다.

홈 화면의 **"지금 울리기(테스트)"** 버튼으로 실제 알람 시각을 기다리지 않고
울림→끄기→(제안) 전체 흐름을 바로 확인할 수 있다.

## ⚠️ 검증 상태 / 알려진 미완성

이 코드는 Dart/Flutter SDK가 없는 환경에서 작성되어 **`flutter analyze`/`flutter test`로
아직 검증되지 않았다.** 로컬에서 `flutter create .`로 플랫폼 폴더(android/ios)를
생성한 뒤 받아야 할 작업:

- **`flutter create .`**: 이 디렉터리엔 `lib/`·`test/`·`pubspec.yaml`만 있다.
  `android/`, `ios/`, 플랫폼 설정은 `flutter create .`로 생성해야 한다.
- **알람음 자산**: `assets/sounds/*.mp3` 파일과 `pubspec.yaml`의 `flutter: assets:` 등록 필요.
- **Android 권한/매니페스트**: `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`,
  `RECEIVE_BOOT_COMPLETED`, 알림 채널, 풀스크린 인텐트 액티비티 설정.
- **알람 콜백 → RingScreen 연결**: `alarm_scheduler._alarmCallback`은 별도 isolate라
  UI에 직접 접근 못 한다. 알림 탭/풀스크린 인텐트로 앱을 RingScreen에 진입시키는
  배선이 기기에서 필요하다.
- **iOS**: android_alarm_manager_plus는 Android 전용. iOS는 로컬 알림 기반 별도 경로 필요.
- **스누즈 재울림**: 현재 onSnooze는 테스트용으로 즉시 재울림 처리. 실제로는 N분 뒤
  재스케줄 + 화면 종료가 필요.
- **전날 수면 시간**: MVP는 기본값(7.5h) 사용. 추정/입력 경로는 후속.

즉 **`lib/core/`(두뇌)는 완성·테스트 대상**이고, 앱 셸은 실기기에서 배선을 마저
해야 하는 골격이다.
