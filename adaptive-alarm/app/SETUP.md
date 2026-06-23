# 로컬 셋업 가이드

이 디렉터리엔 `lib/`·`test/`·`tool/`·`assets/`·`pubspec.yaml`만 있다. 플랫폼 폴더
(`android/`·`ios/`)와 권한·매니페스트는 아래 절차로 채운다. (⚠️ 실기기 검증 필요)

## 1. 플랫폼 폴더 생성

```bash
cd app
flutter create .          # android/ ios/ 등 플랫폼 스캐폴드 생성 (lib/는 유지됨)
flutter pub get
flutter test              # core 포팅 parity 검증
dart run tool/core_check.dart   # (선택) Flutter 없이 core만 검증
```

## 2. 알람음 자산

`assets/sounds/`에 `sound_catalog.dart`가 참조하는 mp3들을 넣는다(같은 폴더 README 참고).
`pubspec.yaml`엔 이미 `assets/sounds/`가 등록돼 있다.

## 3. Android 권한 / 매니페스트

`android/app/src/main/AndroidManifest.xml`의 `<manifest>` 안, `<application>` 위에
권한을 추가한다:

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

`<application>` 안에 android_alarm_manager_plus 리시버/서비스를 등록한다:

```xml
<service
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmService"
    android:permission="android.permission.BIND_JOB_SERVICE"
    android:exported="false"/>
<receiver
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver"
    android:exported="false"/>
<receiver
    android:name="dev.fluttercommunity.plus.androidalarmmanager.RebootBroadcastReceiver"
    android:exported="false">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
  </intent-filter>
</receiver>
```

`MainActivity`가 잠금화면 위로 풀스크린 인텐트로 뜨도록 속성을 추가한다:

```xml
<activity
    android:name=".MainActivity"
    android:showWhenLocked="true"
    android:turnScreenOn="true"
    ... 기존 속성 유지 ... />
```

## 4. 런타임 권한 요청

Android 13+는 `POST_NOTIFICATIONS`, 12+는 정확 알람(`SCHEDULE_EXACT_ALARM`)에 대해
런타임/설정 화면 동의가 필요하다. 앱 첫 실행 시 권한 요청 흐름을 추가한다
(예: `permission_handler` 패키지). MVP 골격에는 아직 없음.

## 5. iOS

`android_alarm_manager_plus`는 Android 전용이다. iOS는 `flutter_local_notifications`의
예약 알림으로 대체 경로를 만들어야 하며, 백그라운드 정확 기상에 OS 제약이 크다.
초기엔 Android 우선으로 진행 권장.

## 검증 상태 요약

| 부분 | 상태 |
|---|---|
| `lib/core/` (점수·추세·판정·엔진) | ✅ Dart 실행으로 검증, Python과 동일 |
| `lib/services`·`lib/ui` (셸) | ⚠️ 코드 작성됨, 실기기 미검증 |
| Android 권한·매니페스트·알람 배선 | ⚠️ 위 절차 적용 후 실기기에서 확인 필요 |
