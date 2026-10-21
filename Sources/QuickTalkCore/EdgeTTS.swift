import Foundation

// [INFO] [FEATURE] 읽어주기(TTS) 엔진 — Apple 시스템 음성 · Microsoft Edge 신경망 음성 · Piper 로컬 음성

/// 읽어주기 엔진. 저장값(rawValue)은 설정 호환을 위해 짧게 둔다.
public enum TTSEngine: String, Codable, CaseIterable {
  case apple = "apple"
  case edge = "edge"
  case piper = "piper"

  public var displayName: String {
    switch self {
    case .apple: return L("Apple 음성 (오프라인)")
    case .edge: return L("Edge TTS (온라인)")
    case .piper: return L("Piper (로컬·오프라인)")
    }
  }

  public var shortName: String {
    switch self {
    case .apple: return L("Apple 음성")
    case .edge: return L("Edge TTS")
    case .piper: return L("Piper")
    }
  }
}

/// Edge TTS 목소리 한 개(신경망 음성).
public struct EdgeVoice: Identifiable, Equatable {
  public enum Gender { case female, male }

  public let id: String          // ko-KR-SunHiNeural
  public let name: String        // SunHi
  public let gender: Gender
  public let locale: String      // ko-KR

  public init(id: String, name: String, gender: Gender, locale: String) {
    self.id = id
    self.name = name
    self.gender = gender
    self.locale = locale
  }

  /// "한국어 · SunHi (여성)" — 언어 이름은 표시 언어 기준
  public var displayName: String {
    "\(SpeechCatalog.languageName(locale)) · \(name) (\(gender == .female ? L("여성") : L("남성")))"
  }
}

/// Edge TTS(온라인) 실행 파일 탐색·인자 구성·목소리 목록.
/// 앱 타깃에서는 이 정보로 `edge-tts` CLI를 실행해 mp3를 받아 재생한다.
public enum EdgeTTS {
  public static let defaultVoice = "ko-KR-SunHiNeural"

  /// 자주 쓰는 신경망 목소리 — 목록에 없으면 목소리 ID를 직접 입력할 수 있다.
  public static let voices: [EdgeVoice] = [
    EdgeVoice(id: "ko-KR-SunHiNeural", name: "SunHi", gender: .female, locale: "ko-KR"),
    EdgeVoice(id: "ko-KR-InJoonNeural", name: "InJoon", gender: .male, locale: "ko-KR"),
    EdgeVoice(id: "ko-KR-HyunsuMultilingualNeural", name: "Hyunsu", gender: .male, locale: "ko-KR"),
    EdgeVoice(id: "en-US-AvaMultilingualNeural", name: "Ava", gender: .female, locale: "en-US"),
    EdgeVoice(id: "en-US-AndrewMultilingualNeural", name: "Andrew", gender: .male, locale: "en-US"),
    EdgeVoice(id: "en-US-AriaNeural", name: "Aria", gender: .female, locale: "en-US"),
    EdgeVoice(id: "en-US-GuyNeural", name: "Guy", gender: .male, locale: "en-US"),
    EdgeVoice(id: "en-GB-SoniaNeural", name: "Sonia", gender: .female, locale: "en-GB"),
    EdgeVoice(id: "en-GB-RyanNeural", name: "Ryan", gender: .male, locale: "en-GB"),
    EdgeVoice(id: "ja-JP-NanamiNeural", name: "Nanami", gender: .female, locale: "ja-JP"),
    EdgeVoice(id: "ja-JP-KeitaNeural", name: "Keita", gender: .male, locale: "ja-JP"),
    EdgeVoice(id: "zh-CN-XiaoxiaoNeural", name: "Xiaoxiao", gender: .female, locale: "zh-CN"),
    EdgeVoice(id: "zh-CN-YunxiNeural", name: "Yunxi", gender: .male, locale: "zh-CN"),
  ]

  /// 언어(ko-KR 등)에 맞는 목소리만. 없으면 전체.
  public static func voices(matching language: String) -> [EdgeVoice] {
    let list = voices.filter { $0.locale == language }
    return list.isEmpty ? voices : list
  }

  public static func voice(id: String) -> EdgeVoice? {
    voices.first { $0.id == id }
  }

  /// 실행 파일 후보 — Finder에서 띄운 앱은 PATH가 최소라 절대 경로로 찾는다.
  public static func binaryPath(custom: String = "") -> URL? {
    var candidates: [String] = []
    let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { candidates.append(trimmed) }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    candidates += [
      "\(home)/.venvs/edge-tts/bin/edge-tts",
      "\(home)/.local/bin/edge-tts",
      "/opt/homebrew/bin/edge-tts",
      "/usr/local/bin/edge-tts",
    ]
    guard let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else { return nil }
    return URL(fileURLWithPath: hit)
  }

  public static func isInstalled(custom: String = "") -> Bool {
    binaryPath(custom: custom) != nil
  }

  /// 설정 창 상태 행 — 설치 경로까지 보여 준다.
  public static func status(custom: String = "") -> String {
    guard let url = binaryPath(custom: custom) else { return L("설치되지 않음") }
    return Lf("준비됨 — %@", url.path)
  }

  /// AVSpeechUtterance 속도(0.35~0.62) → Edge `--rate` 퍼센트(-50% ~ +55%).
  /// 설정 슬라이더를 두 엔진이 함께 쓰므로 Apple 기준 값을 Edge 눈금으로 옮긴다.
  public static func ratePercent(fromRate rate: Double) -> Int {
    let pct = (rate - 0.48) / 0.13 * 50.0
    let clamped = min(max(pct, -50), 55)
    return Int((clamped / 5).rounded()) * 5
  }

  /// `--rate` 값 — 부호를 반드시 붙인다(edge-tts 규칙).
  public static func rateArgument(percent: Int) -> String {
    "\(percent >= 0 ? "+" : "")\(percent)%"
  }

  /// edge-tts CLI 인자 — mp3 한 파일로 받는다.
  public static func arguments(text: String, voice: String, ratePercent: Int, outputPath: String) -> [String] {
    ["--voice", voice.isEmpty ? defaultVoice : voice,
     "--text", text,
     "--rate", rateArgument(percent: ratePercent),
     "--write-media", outputPath]
  }
}
