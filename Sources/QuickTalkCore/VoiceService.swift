import Foundation

public enum VoiceEngine: String, Codable, CaseIterable {
  case apple = "Apple 음성인식"
  case whisper = "Whisper 로컬"

  /// 화면 표시 이름 — 저장값(rawValue)은 기존 설정 호환을 위해 그대로 둔다
  public var displayName: String {
    switch self {
    case .apple: return L("Apple 음성")
    case .whisper: return L("Whisper (로컬)")
    }
  }
}

public enum VoiceService {
  // Apple: SFSpeechRecognizer는 App 타깃에서 권한 요청 (Info.plist 키 이미 존재).
  // Whisper: whisper.cpp 모델 파일 경로만 Core가 보관, 실추론은 App 타깃/별도 모듈.
  public static var whisperDefaultPath: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/QuickTalk/models/ggml-base.bin")
  }
}
