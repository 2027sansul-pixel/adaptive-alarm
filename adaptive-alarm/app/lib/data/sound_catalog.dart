// 앱이 들고 있는 알람음 카탈로그와 음원별 모집단 기준선.
//
// features = [tempo, pitch, brightness] 정규화 0~1. assetPath는 실제 음원 파일.
// (sim/generate.py 의 CATALOG와 같은 음향 좌표를 쓴다.)

import '../core/models.dart';

class SoundAsset {
  final SoundProfile profile;
  final String label; // UI 표시 이름
  final String assetPath; // assets/sounds/*.mp3

  const SoundAsset(this.profile, this.label, this.assetPath);
}

const List<SoundAsset> kSoundCatalog = [
  SoundAsset(SoundProfile('morning_bells', 0.9, [0.6, 0.7, 0.8], 'melodic'),
      '모닝 벨', 'assets/sounds/morning_bells.mp3'),
  SoundAsset(SoundProfile('piano_rise', 0.85, [0.7, 0.5, 0.9], 'melodic'),
      '피아노 라이즈', 'assets/sounds/piano_rise.mp3'),
  SoundAsset(SoundProfile('classic_beep', 0.2, [0.5, 0.9, 0.5], 'beep'),
      '클래식 비프', 'assets/sounds/classic_beep.mp3'),
  SoundAsset(SoundProfile('deep_horn', 0.1, [0.3, 0.1, 0.2], 'harsh'),
      '딥 혼', 'assets/sounds/deep_horn.mp3'),
  SoundAsset(SoundProfile('soft_chimes', 0.8, [0.4, 0.6, 0.7], 'melodic'),
      '소프트 차임', 'assets/sounds/soft_chimes.mp3'),
];

List<SoundProfile> get catalogProfiles =>
    kSoundCatalog.map((s) => s.profile).toList();

SoundAsset soundAssetById(String id) =>
    kSoundCatalog.firstWhere((s) => s.profile.soundId == id);

/// 콜드스타트용 음원별 모집단 기준선 [평균, 표준편차].
/// 초기엔 비워 두면 엔진이 kDefaultPrior(3.6, 0.7)을 쓴다. 나중에 서버 집계로 채움.
const Map<String, List<double>> kSoundPriors = {};
