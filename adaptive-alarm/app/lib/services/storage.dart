// 엔진 상태와 알람 설정의 영속화 (shared_preferences에 JSON).
//
// 앱이 종료되거나 기기가 재부팅돼도 추세 데이터가 남아야 하므로 매일 저장한다.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/engine.dart';
import '../data/sound_catalog.dart';

class AppStorage {
  static const _kEngine = 'engine_state_v1';
  static const _kDayIndex = 'day_index_v1';
  static const _kAlarmHour = 'alarm_hour_v1';
  static const _kAlarmMinute = 'alarm_minute_v1';
  static const _kEnabled = 'alarm_enabled_v1';
  static const _kFirstDateMs = 'first_date_ms_v1'; // dayIndex 계산 기준일

  final SharedPreferences _prefs;
  AppStorage(this._prefs);

  static Future<AppStorage> open() async =>
      AppStorage(await SharedPreferences.getInstance());

  // ---- 엔진 ----
  AlarmEngine loadEngine() {
    final raw = _prefs.getString(_kEngine);
    if (raw == null) {
      // 첫 실행: 카탈로그의 첫 음원으로 시작
      return AlarmEngine.create(
        catalogProfiles,
        kSoundCatalog.first.profile.soundId,
        priors: kSoundPriors,
      );
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return AlarmEngine.fromJson(catalogProfiles, data, priors: kSoundPriors);
  }

  Future<void> saveEngine(AlarmEngine engine) async {
    await _prefs.setString(_kEngine, jsonEncode(engine.toJson()));
  }

  // ---- dayIndex: 첫 사용일로부터 경과 일수 ----
  int currentDayIndex(DateTime now) {
    var firstMs = _prefs.getInt(_kFirstDateMs);
    if (firstMs == null) {
      final midnight = DateTime(now.year, now.month, now.day);
      firstMs = midnight.millisecondsSinceEpoch;
      _prefs.setInt(_kFirstDateMs, firstMs);
    }
    final first = DateTime.fromMillisecondsSinceEpoch(firstMs);
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(first).inDays;
  }

  // ---- 알람 설정 ----
  int get alarmHour => _prefs.getInt(_kAlarmHour) ?? 7;
  int get alarmMinute => _prefs.getInt(_kAlarmMinute) ?? 0;
  bool get enabled => _prefs.getBool(_kEnabled) ?? false;

  Future<void> setAlarm(int hour, int minute, bool enabled) async {
    await _prefs.setInt(_kAlarmHour, hour);
    await _prefs.setInt(_kAlarmMinute, minute);
    await _prefs.setBool(_kEnabled, enabled);
  }
}
