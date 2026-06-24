# 알람음 자산

`lib/data/sound_catalog.dart`의 `assetPath`와 파일명이 일치해야 한다.

필요한 파일:
- `morning_bells.mp3`
- `piano_rise.mp3`
- `classic_beep.mp3`
- `deep_horn.mp3`
- `soft_chimes.mp3`

(저작권 자유 음원을 넣을 것. 카탈로그의 melodyScore/features/category는 각 음원의
실제 음향 특성에 맞게 조정한다.)

## 음원 개수에 대해

알람음은 많을수록 습관화 회피에 유리하지만, **지금은 위 5개로 시작한다.**
음원이 늘면 음원별 기준선·추세(`TrendState`)와 교체 후보 선택(`decision.py`)이
음원 수만큼 늘어나 전체 흐름 검증이 복잡해진다. 5개로 end-to-end 동작을
확인한 뒤 카테고리(벨/피아노/비프/혼/차임)별로 점진 확장한다.
새 음원 추가는 `sound_catalog.dart`에 항목을 더하고 mp3를 여기 넣으면 되며,
코어 로직은 음원 개수에 종속되지 않는다.
