QuickTalk 메뉴바 아이콘 - 크게 만든 버전
============================================

이전 얇은 라인 아이콘보다 훨씬 두껍고 꽉 찬 솔리드 형태로 만들었습니다.
옆에 있는 안드로이드/다른 앱 아이콘들과 비슷한 시각적 무게감.

파일:
- QuickTalk_MenuBar_Black_XX : 라이트 모드용 (검정) - 템플릿으로 사용
  NSImage.isTemplate = true 설정하면 다크모드에서 자동으로 흰색으로 반전됩니다.
- QuickTalk_MenuBar_White_XX : 다크모드/활성 상태용 (흰색)
- Template.png / @2x : 실제 앱에 넣을 대표 파일
- Original_Big : 패딩 최소화된 원본 (메뉴바에서 가장 크게 보이는 버전)

사용법:
statusItem.button?.image = NSImage(named: "QuickTalk_MenuBar_Template")
statusItem.button?.image?.isTemplate = true
statusItem.button?.image?.size = NSSize(width: 18, height: 18) // 18~20 추천

크기 추천: 메뉴바에서는 18~22px가 옆 아이콘들과 가장 비슷한 크기입니다.
이전보다 패딩을 80% 줄여서 같은 18px라도 훨씬 커 보입니다.
