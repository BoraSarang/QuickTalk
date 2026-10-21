import Foundation

/// 새 대화 창(독립 창)을 띄울 위치 — 메뉴바 아이콘 하단 고정은 쓰지 않는다.
public enum NewWindowPosition: String, Codable, CaseIterable, Identifiable {
  case center
  case mousePointer

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .center: return L("화면 중앙")
    case .mousePointer: return L("마우스 포인터")
    }
  }
}

public struct QuickTalkSettings: Codable, Equatable {
  public var showMenuBarIcon: Bool = true
  public var showDockIcon: Bool = false
  /// 화면 테마 — 시스템/라이트/다크 (기본: 시스템)
  public var appearance: AppAppearance = .system
  /// 표시 언어 — 시스템 기본/한국어/English (기본: 시스템)
  public var language: AppLanguage = .system
  /// 단축키로 새로 열 때 마지막 대화를 이어가는 유지 시간(분). **0 = 사용 안 함(언제나 새 대화)**.
  /// 예: 10 → 마지막 대화가 10분 안에 있었으면 이어서, 지났으면 새 대화(기본 10분).
  public var shortcutSessionMinutes: Int = 10
  public static let sessionMinuteOptions: [Int] = [5, 10, 30, 0]
  /// 대화 창을 항상 위에 둘지(헤더 📌). 기본은 꺼짐 — 설정·시스템 권한 창을 가리지 않게.
  public var alwaysOnTop: Bool = false
  public var previewLines: Int = 2
  public var keepDays: Int = 30
  public var globalShortcut: String = "Cmd+Space"
  /// 새 대화 창 위치 (기본: 화면 중앙 / 마우스 포인터 선택 가능)
  public var newWindowPosition: NewWindowPosition = .center
  /// 퀵셸프 열기/닫기(기본 ⌥⌘V)
  public var shelfShortcut: String = "Option+Shift+V"
  /// 캡처 — 전체 화면(기본 ⌥⇧3)
  public var captureFullShortcut: String = "Option+Shift+3"
  /// 캡처 — 드래그 선택(기본 ⌥⇧4)
  public var captureRegionShortcut: String = "Option+Shift+4"
  /// 캡처 — 윈도우(기본 ⌥⇧⌘4)
  public var captureWindowShortcut: String = "Option+Shift+Cmd+4"

  // AI 프로바이더 — 기본 3종(Local Apple FM / Local Ollama / Remote OpenAI 호환) 시드 후 추가·삭제 가능
  public var providers: [LLMProviderConfig] = LLMProviderConfig.defaultProviders()
  public var activeProviderID: String = LLMProviderConfig.appleFMID
  /// 예비 프로바이더 ID("" = 사용 안 함). 주 모델이 429·5xx·시간 초과로 실패하면 **1회만** 넘어간다.
  /// 구버전 설정에는 없는 값이므로 비어 있으면 폴백하지 않는다(동작 변화 없음).
  public var fallbackProviderID: String = ""

  // 음성 (2종 지원)
  public var voiceEngine: VoiceEngine = .apple
  /// whisper.cpp 모델 경로(ggml-*.bin)
  public var whisperModelPath: String = ""
  /// Whisper 백엔드 — 자동(설치된 것 우선) / mlx-whisper / whisper.cpp
  public var whisperBackend: WhisperBackend = .auto
  /// mlx-whisper 모델 폴더(비우면 감지된 모델 자동)
  public var whisperMLXModelPath: String = ""
  /// 전사 언어("" = 자동 감지). 짧은 음성은 자동 감지가 영어로 새는 일이 잦아 기본 한국어
  public var whisperLanguage: String = "ko"
  /// 모델을 찾을 폴더(비우면 기본 위치: ~/Documents/Files/whisper · 앱 지원 폴더)
  public var whisperModelFolder: String = ""
  /// Apple 받아쓰기 언어(Bcp-47, "" = 시스템 기본: 한국어 우선)
  public var appleSpeechLocale: String = ""
  /// 읽어주기(TTS) 언어 — 기본 한국어
  public var ttsLanguage: String = "ko-KR"
  /// 읽어주기 목소리 식별자("" = 그 언어의 시스템 기본 목소리)
  public var ttsVoiceID: String = ""
  /// 읽어주기 속도(AVSpeechUtterance: 0.5가 기본, 낮을수록 느림)
  public var ttsRate: Double = 0.48
  /// 읽어주기 엔진 — Apple 시스템 음성(오프라인) / Edge TTS(온라인 신경망)
  public var ttsEngine: TTSEngine = .apple
  /// Edge TTS 목소리 ID("" = 기본 한국어 목소리)
  public var edgeVoice: String = EdgeTTS.defaultVoice
  /// Edge TTS 실행 파일 경로("" = 자동 탐색: ~/.venvs/edge-tts/bin · Homebrew · /usr/local/bin)
  public var edgeBinaryPath: String = ""
  /// Piper 모델(.onnx 파일 또는 그 폴더, "" = 기본 폴더 자동 탐색)
  public var piperModelPath: String = ""
  /// Piper 실행 파일 경로("" = 자동 탐색: ~/.venvs/piper/bin · Homebrew · /usr/local/bin)
  public var piperBinaryPath: String = ""

  // QuickShelf (PLAN_v0.13) — 단축키·헤더 버튼으로 여는 허브
  // 화면 가장자리 핸들 표시는 제거했다(2026-10-21 사용자 결정).
  /// 캡처 직후 클립보드에도 복사(다른 앱에서 바로 붙여넣기)
  public var shelfCopyCaptureToClipboard: Bool = true

  // 웹 검색 (PLAN_v0.14) — 답변을 만들기 전에 검색 결과를 프롬프트에 주입한다.
  /// 검색 공급자 — `none`이면 외부 요청을 전혀 보내지 않는다.
  public var webSearchProvider: WebSearchProvider = .none
  /// 검색 결과 수(3...8)
  public var webSearchResultCount: Int = 5
  public static let webSearchCountOptions: [Int] = [3, 5, 8]
  /// 신선도 — Exa `startPublishedDate`
  public var webSearchFreshness: WebSearchFreshness = .week
  /// 결과 1건의 최대 글자 수(500...4000)
  public var webSearchMaxCharacters: Int = 2_000
  /// Exa 키를 저장한 `SecretStore` 계정 이름(키 자체는 설정 JSON에 넣지 않는다)
  public var exaSecretID: String = "exa-api-key"
  /// 하루 검색 상한(0 = 무제한). Exa 무료 크레딧을 보호하기 위한 로컬 카운터다.
  public var webSearchDailyLimit: Int = 50
  /// 카운터가 속한 날짜(yyyy-MM-dd, 로컬 시간). 날이 바뀌면 0으로 리셋한다.
  public var webSearchUsageDay: String = ""
  /// 오늘 네트워크 검색 횟수(캐시 적중은 세지 않는다).
  public var webSearchUsageCount: Int = 0
  public static let webSearchDailyLimitOptions: [Int] = [0, 20, 50, 100, 200]
  /// 검색을 답변에 넣는 방식 — 기존 프롬프트 주입 / 모델 툴 콜링 / Exa `/answer`(2026-10-21 P3).
  public var webSearchMode: WebSearchMode = .inject

  // 공통 메모리 (PLAN_v0.16) — 모든 대화에 적용되는 사용자 작성 사실.
  /// 공통 메모리 사용 여부(기본 켜짐). 꺼도 저장된 항목은 남는다.
  public var globalMemoryEnabled: Bool = true
  /// 주입 방식 — 항상 모두 / 관련 항목만.
  public var globalMemoryMode: MemoryInjectionMode = .always
  /// 요청에 넣을 공통 메모리 토큰 예산(머리말 포함).
  public var globalMemoryBudgetTokens: Int = 800
  public static let globalMemoryBudgetOptions: [Int] = [400, 800, 1_600, 3_200]

  // 대화 기억 정리 (T-71) — 길어지면 오래된 턴을 요약해 첫 토큰 지연·비용을 줄인다.
  /// 자동 정리 사용 여부(기본 켜짐). 꺼도 원문은 그대로 전송된다.
  public var autoCompact: Bool = true
  /// 요약하지 않고 원문으로 남길 최근 메시지 수(짝을 맞추기 위해 짝수로 보정).
  public var compactKeepTurns: Int = 6
  public static let compactKeepOptions: [Int] = [4, 6, 8, 12]

  /// 검색이 켜져 있는가(공급자 선택 기준)
  public var webSearchEnabled: Bool { webSearchProvider != .none }

  public init() {}

  // MARK: - 표시 정책 (진입점 최소 1개 보장)

  /// 메뉴바 상주 앱이라 메뉴바·Dock을 모두 숨기면 다시 열 방법이 없다.
  /// 메뉴바를 숨기면 Dock을 자동으로 켜서 진입점을 남긴다.
  public mutating func setMenuBarIcon(_ visible: Bool) {
    showMenuBarIcon = visible
    if !visible { showDockIcon = true }
  }

  /// Dock을 숨기면 메뉴바를 자동으로 켠다(같은 이유).
  public mutating func setDockIcon(_ visible: Bool) {
    showDockIcon = visible
    if !visible { showMenuBarIcon = true }
  }

  /// 저장된 설정이 둘 다 숨김이면 Dock을 켜서 진입점을 만든다. 변경 여부를 반환.
  @discardableResult
  public mutating func normalizeVisibility() -> Bool {
    guard !showMenuBarIcon, !showDockIcon else { return false }
    showDockIcon = true
    return true
  }

  // MARK: - 단축키 세션 규칙

  /// 마지막 활동이 유지 시간(`shortcutSessionMinutes`) 안이면 이어서 연다.
  /// `0`(사용 안 함)·활동 기록 없음 → false(새 대화).
  public func continuesSession(lastActivity: Date?, now: Date = Date()) -> Bool {
    guard shortcutSessionMinutes > 0, let lastActivity else { return false }
    return now.timeIntervalSince(lastActivity) < TimeInterval(shortcutSessionMinutes * 60)
  }

  public var sessionMinutesLabel: String {
    shortcutSessionMinutes == 0 ? L("사용 안 함") : Lf("%d분", shortcutSessionMinutes)
  }

  /// 활성 프로바이더 — ID 미일치/비활성 시 사용 가능한 첫 항목으로 폴백
  public var activeProvider: LLMProviderConfig? {
    providers.first { $0.id == activeProviderID && $0.enabled } ?? providers.first { $0.enabled }
  }

  public func provider(_ id: String) -> LLMProviderConfig? { providers.first { $0.id == id } }

  /// 예비 프로바이더 — 주 모델과 다르고, 사용 중이며, 존재할 때만.
  /// 준비 상태(키·모델·주소)는 호출 직전에 `ProviderFallback.isUsable`로 한 번 더 확인한다.
  public var fallbackProvider: LLMProviderConfig? {
    guard !fallbackProviderID.isEmpty,
          fallbackProviderID != activeProviderID,
          let p = providers.first(where: { $0.id == fallbackProviderID }), p.enabled
    else { return nil }
    return p
  }

  // MARK: - Codable (v0.9 이전 단일 프로바이더 설정 마이그레이션 포함)

  private enum CodingKeys: String, CodingKey {
    case showMenuBarIcon, showDockIcon, shortcutSessionMinutes, alwaysOnTop
    case appearance, language
    case previewLines, keepDays, globalShortcut
    case shelfShortcut, captureFullShortcut, captureRegionShortcut, captureWindowShortcut
    case newWindowPosition
    case providers, activeProviderID, fallbackProviderID
    case voiceEngine, whisperModelPath
    case whisperBackend, whisperMLXModelPath, whisperLanguage, whisperModelFolder
    case appleSpeechLocale, ttsLanguage, ttsVoiceID, ttsRate
    case ttsEngine, edgeVoice, edgeBinaryPath
    case piperModelPath, piperBinaryPath
    case shelfCopyCaptureToClipboard
    case webSearchProvider, webSearchResultCount
    case webSearchFreshness, webSearchMaxCharacters, exaSecretID
    case webSearchDailyLimit, webSearchUsageDay, webSearchUsageCount, webSearchMode
    case autoCompact, compactKeepTurns
    case globalMemoryEnabled, globalMemoryMode, globalMemoryBudgetTokens
    // 구버전 전용 (디코딩 승계용 — 인코딩에는 기록하지 않는다)
    case llmProvider, openAIBaseURL, openAIModel, ollamaHost, ollamaModel, apiKeyAccount
  }

  /// 알 수 없는 enum 값(다운그레이드·손상)이면 그 항목만 기본값으로 두고 나머지 설정은 살린다.
  /// `decodeIfPresent(Enum.self)`는 unknown raw value에서 throw해 **전체 설정을 잃을 수 있다**.
  private static func decodeEnum<T: RawRepresentable>(
    _ type: T.Type,
    _ c: KeyedDecodingContainer<CodingKeys>,
    _ key: CodingKeys,
    default fallback: T
  ) -> T where T.RawValue == String {
    guard let raw = try? c.decodeIfPresent(String.self, forKey: key),
          let value = T(rawValue: raw) else { return fallback }
    return value
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
    appearance = Self.decodeEnum(AppAppearance.self, c, .appearance, default: .system)
    language = Self.decodeEnum(AppLanguage.self, c, .language, default: .system)
    shortcutSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .shortcutSessionMinutes) ?? 10
    alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
    previewLines = try c.decodeIfPresent(Int.self, forKey: .previewLines) ?? 2
    keepDays = try c.decodeIfPresent(Int.self, forKey: .keepDays) ?? 30
    globalShortcut = try c.decodeIfPresent(String.self, forKey: .globalShortcut) ?? "Cmd+Space"
    shelfShortcut = try c.decodeIfPresent(String.self, forKey: .shelfShortcut) ?? "Option+Shift+V"
    captureFullShortcut = try c.decodeIfPresent(String.self, forKey: .captureFullShortcut) ?? "Option+Shift+3"
    captureRegionShortcut = try c.decodeIfPresent(String.self, forKey: .captureRegionShortcut) ?? "Option+Shift+4"
    captureWindowShortcut = try c.decodeIfPresent(String.self, forKey: .captureWindowShortcut) ?? "Option+Shift+Cmd+4"
    newWindowPosition = Self.decodeEnum(NewWindowPosition.self, c, .newWindowPosition, default: .center)
    voiceEngine = Self.decodeEnum(VoiceEngine.self, c, .voiceEngine, default: .apple)
    whisperModelPath = try c.decodeIfPresent(String.self, forKey: .whisperModelPath) ?? ""
    whisperBackend = Self.decodeEnum(WhisperBackend.self, c, .whisperBackend, default: .auto)
    whisperMLXModelPath = try c.decodeIfPresent(String.self, forKey: .whisperMLXModelPath) ?? ""
    whisperLanguage = try c.decodeIfPresent(String.self, forKey: .whisperLanguage) ?? "ko"
    whisperModelFolder = try c.decodeIfPresent(String.self, forKey: .whisperModelFolder) ?? ""
    appleSpeechLocale = try c.decodeIfPresent(String.self, forKey: .appleSpeechLocale) ?? ""
    ttsLanguage = try c.decodeIfPresent(String.self, forKey: .ttsLanguage) ?? "ko-KR"
    ttsVoiceID = try c.decodeIfPresent(String.self, forKey: .ttsVoiceID) ?? ""
    ttsRate = try c.decodeIfPresent(Double.self, forKey: .ttsRate) ?? 0.48
    ttsEngine = Self.decodeEnum(TTSEngine.self, c, .ttsEngine, default: .apple)
    edgeVoice = try c.decodeIfPresent(String.self, forKey: .edgeVoice) ?? EdgeTTS.defaultVoice
    edgeBinaryPath = try c.decodeIfPresent(String.self, forKey: .edgeBinaryPath) ?? ""
    piperModelPath = try c.decodeIfPresent(String.self, forKey: .piperModelPath) ?? ""
    piperBinaryPath = try c.decodeIfPresent(String.self, forKey: .piperBinaryPath) ?? ""
    shelfCopyCaptureToClipboard = try c.decodeIfPresent(Bool.self, forKey: .shelfCopyCaptureToClipboard) ?? true
    webSearchProvider = Self.decodeEnum(WebSearchProvider.self, c, .webSearchProvider, default: .none)
    webSearchResultCount = try c.decodeIfPresent(Int.self, forKey: .webSearchResultCount) ?? 5
    webSearchFreshness = Self.decodeEnum(WebSearchFreshness.self, c, .webSearchFreshness, default: .week)
    webSearchMaxCharacters = try c.decodeIfPresent(Int.self, forKey: .webSearchMaxCharacters) ?? 2_000
    exaSecretID = try c.decodeIfPresent(String.self, forKey: .exaSecretID) ?? "exa-api-key"
    webSearchDailyLimit = try c.decodeIfPresent(Int.self, forKey: .webSearchDailyLimit) ?? 50
    webSearchUsageDay = try c.decodeIfPresent(String.self, forKey: .webSearchUsageDay) ?? ""
    webSearchUsageCount = try c.decodeIfPresent(Int.self, forKey: .webSearchUsageCount) ?? 0
    webSearchMode = Self.decodeEnum(WebSearchMode.self, c, .webSearchMode, default: .inject)
    autoCompact = try c.decodeIfPresent(Bool.self, forKey: .autoCompact) ?? true
    compactKeepTurns = try c.decodeIfPresent(Int.self, forKey: .compactKeepTurns) ?? 6
    globalMemoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalMemoryEnabled) ?? true
    globalMemoryMode = Self.decodeEnum(MemoryInjectionMode.self, c, .globalMemoryMode, default: .always)
    globalMemoryBudgetTokens = try c.decodeIfPresent(Int.self, forKey: .globalMemoryBudgetTokens) ?? 800

    if let stored = try c.decodeIfPresent([LLMProviderConfig].self, forKey: .providers), !stored.isEmpty {
      providers = stored
      activeProviderID = try c.decodeIfPresent(String.self, forKey: .activeProviderID)
        ?? stored.first?.id ?? LLMProviderConfig.appleFMID
      // 구버전 설정에는 없는 값 — 없으면 "사용 안 함"(동작 변화 없음)
      fallbackProviderID = try c.decodeIfPresent(String.self, forKey: .fallbackProviderID) ?? ""
    } else {
      let legacy = try c.decodeIfPresent(LegacyLLMProviderKind.self, forKey: .llmProvider)
      providers = try Self.migratedProviders(from: c, legacy: legacy)
      activeProviderID = legacy?.providerID ?? LLMProviderConfig.appleFMID
    }
  }

  /// 구버전 키(llmProvider 등)는 다시 쓰지 않는다 — 신규 키만 기록.
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
    try c.encode(showDockIcon, forKey: .showDockIcon)
    try c.encode(appearance, forKey: .appearance)
    try c.encode(language, forKey: .language)
    try c.encode(shortcutSessionMinutes, forKey: .shortcutSessionMinutes)
    try c.encode(alwaysOnTop, forKey: .alwaysOnTop)
    try c.encode(previewLines, forKey: .previewLines)
    try c.encode(keepDays, forKey: .keepDays)
    try c.encode(globalShortcut, forKey: .globalShortcut)
    try c.encode(shelfShortcut, forKey: .shelfShortcut)
    try c.encode(captureFullShortcut, forKey: .captureFullShortcut)
    try c.encode(captureRegionShortcut, forKey: .captureRegionShortcut)
    try c.encode(captureWindowShortcut, forKey: .captureWindowShortcut)
    try c.encode(newWindowPosition, forKey: .newWindowPosition)
    try c.encode(providers, forKey: .providers)
    try c.encode(activeProviderID, forKey: .activeProviderID)
    try c.encode(fallbackProviderID, forKey: .fallbackProviderID)
    try c.encode(voiceEngine, forKey: .voiceEngine)
    try c.encode(whisperModelPath, forKey: .whisperModelPath)
    try c.encode(whisperBackend, forKey: .whisperBackend)
    try c.encode(whisperMLXModelPath, forKey: .whisperMLXModelPath)
    try c.encode(whisperLanguage, forKey: .whisperLanguage)
    try c.encode(whisperModelFolder, forKey: .whisperModelFolder)
    try c.encode(appleSpeechLocale, forKey: .appleSpeechLocale)
    try c.encode(ttsLanguage, forKey: .ttsLanguage)
    try c.encode(ttsVoiceID, forKey: .ttsVoiceID)
    try c.encode(ttsRate, forKey: .ttsRate)
    try c.encode(ttsEngine, forKey: .ttsEngine)
    try c.encode(edgeVoice, forKey: .edgeVoice)
    try c.encode(edgeBinaryPath, forKey: .edgeBinaryPath)
    try c.encode(piperModelPath, forKey: .piperModelPath)
    try c.encode(piperBinaryPath, forKey: .piperBinaryPath)
    try c.encode(shelfCopyCaptureToClipboard, forKey: .shelfCopyCaptureToClipboard)
    try c.encode(webSearchProvider, forKey: .webSearchProvider)
    try c.encode(webSearchResultCount, forKey: .webSearchResultCount)
    try c.encode(webSearchFreshness, forKey: .webSearchFreshness)
    try c.encode(webSearchMaxCharacters, forKey: .webSearchMaxCharacters)
    try c.encode(exaSecretID, forKey: .exaSecretID)
    try c.encode(webSearchDailyLimit, forKey: .webSearchDailyLimit)
    try c.encode(webSearchUsageDay, forKey: .webSearchUsageDay)
    try c.encode(webSearchUsageCount, forKey: .webSearchUsageCount)
    try c.encode(webSearchMode, forKey: .webSearchMode)
    try c.encode(autoCompact, forKey: .autoCompact)
    try c.encode(compactKeepTurns, forKey: .compactKeepTurns)
    try c.encode(globalMemoryEnabled, forKey: .globalMemoryEnabled)
    try c.encode(globalMemoryMode, forKey: .globalMemoryMode)
    try c.encode(globalMemoryBudgetTokens, forKey: .globalMemoryBudgetTokens)
  }

  /// 구버전 단일 프로바이더 설정값을 기본 3종 목록으로 승계한다.
  /// - 구버전에서 **실제로 활성이던 종류**의 값만 승계한다(기본값이 덮어쓰이지 않도록).
  /// - 비밀 저장소에 그 계정의 값이 실제로 있을 때만 secretID를 승계한다.
  private static func migratedProviders(from c: KeyedDecodingContainer<CodingKeys>,
                                        legacy: LegacyLLMProviderKind?) throws -> [LLMProviderConfig] {
    var list = LLMProviderConfig.defaultProviders()
    func update(_ id: String, _ apply: (inout LLMProviderConfig) -> Void) {
      guard let i = list.firstIndex(where: { $0.id == id }) else { return }
      apply(&list[i])
    }

    if legacy == .openAI {
      if let v = try c.decodeIfPresent(String.self, forKey: .openAIBaseURL), !v.isEmpty {
        update(LLMProviderConfig.remoteOpenAIID) { $0.baseURL = v }
      }
      if let v = try c.decodeIfPresent(String.self, forKey: .openAIModel), !v.isEmpty {
        update(LLMProviderConfig.remoteOpenAIID) { $0.model = v }
      }
    }
    if legacy == .ollama {
      if let v = try c.decodeIfPresent(String.self, forKey: .ollamaHost), !v.isEmpty {
        update(LLMProviderConfig.ollamaID) { $0.baseURL = v }
      }
      if let v = try c.decodeIfPresent(String.self, forKey: .ollamaModel), !v.isEmpty {
        update(LLMProviderConfig.ollamaID) { $0.model = v }
      }
    }

    if let legacySecretID = try c.decodeIfPresent(String.self, forKey: .apiKeyAccount),
       !legacySecretID.isEmpty, legacySecretID != LLMProviderConfig.remoteOpenAIID,
       SecretStore.has(account: legacySecretID),
       !SecretStore.has(account: LLMProviderConfig.remoteOpenAIID) {
      update(LLMProviderConfig.remoteOpenAIID) { $0.secretID = legacySecretID }
    }
    return list
  }
}
