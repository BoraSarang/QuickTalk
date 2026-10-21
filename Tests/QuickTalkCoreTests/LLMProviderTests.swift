import XCTest
@testable import QuickTalkCore

final class LLMProviderTests: XCTestCase {

  func testDefaultProvidersAreThreeWithExpectedShape() {
    let p = LLMProviderConfig.defaultProviders()
    XCTAssertEqual(p.count, 3)
    XCTAssertEqual(p.map(\.type), [.appleFM, .ollama, .openAICompatible])
    XCTAssertEqual(p[0].name, "Local Apple FM")
    XCTAssertEqual(p[1].name, "Local Ollama")
    XCTAssertEqual(p[2].name, "Remote OpenAI 호환")
    XCTAssertEqual(p[0].name, "Local Apple FM")
    XCTAssertEqual(p[1].name, "Local Ollama")
    XCTAssertEqual(p[2].name, "Remote OpenAI 호환")
    XCTAssertEqual(p[2].baseURL, "http://192.168.86.30:8791/v1")
    XCTAssertEqual(p[2].secretID, LLMProviderConfig.remoteOpenAIID)
    XCTAssertTrue(p[2].enabled)
  }

  func testDefaultActiveProviderIsAppleFM() {
    let s = QuickTalkSettings()
    XCTAssertEqual(s.activeProviderID, LLMProviderConfig.appleFMID)
    XCTAssertEqual(s.activeProvider?.type, .appleFM)
  }

  func testActiveProviderFallsBackToEnabledWhenIDMissing() {
    var s = QuickTalkSettings()
    s.activeProviderID = "does-not-exist"
    XCTAssertEqual(s.activeProvider?.id, LLMProviderConfig.appleFMID)
  }

  func testSettingsRoundTripKeepsProviders() throws {
    var s = QuickTalkSettings()
    s.providers[2].model = "my-model"
    s.activeProviderID = LLMProviderConfig.remoteOpenAIID
    s.providers.append(LLMProviderConfig(name: "사내 게이트웨이", type: .openAICompatible,
                                        baseURL: "http://10.0.0.5:8000/v1", model: "gpt-oss"))
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.providers.count, 4)
    XCTAssertEqual(back.activeProviderID, LLMProviderConfig.remoteOpenAIID)
    XCTAssertEqual(back.activeProvider?.model, "my-model")
    XCTAssertEqual(back.providers.last?.name, "사내 게이트웨이")
  }

  func testLegacySettingsMigrateOllamaValues() throws {
    let legacy = """
    {"showMenuBarIcon":true,"globalShortcut":"Cmd+Space","llmProvider":"Ollama 로컬",
     "ollamaHost":"http://localhost:11500","ollamaModel":"qwen2.5:7b"}
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertEqual(s.providers.count, 3)
    XCTAssertEqual(s.activeProviderID, LLMProviderConfig.ollamaID)
    XCTAssertEqual(s.activeProvider?.baseURL, "http://localhost:11500")
    XCTAssertEqual(s.activeProvider?.model, "qwen2.5:7b")
  }

  func testLegacyOpenAIValuesInheritOnlyWhenLegacyActiveWasOpenAI() throws {
    let legacy = """
    {"llmProvider":"OpenAI 호환","openAIBaseURL":"https://api.openai.com/v1",
     "openAIModel":"gpt-4o-mini","apiKeyAccount":"openai"}
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertEqual(s.activeProviderID, LLMProviderConfig.remoteOpenAIID)
    let remote = s.provider(LLMProviderConfig.remoteOpenAIID)
    XCTAssertEqual(remote?.baseURL, "https://api.openai.com/v1")
    XCTAssertEqual(remote?.model, "gpt-4o-mini")
  }

  func testLegacySettingsDoNotOverrideNewDefaultsWhenKindIsAppleFM() throws {
    // 구버전 기본값(llama3.1 / api.openai.com)이 새 기본 프로바이더를 덮어쓰면 안 된다.
    let legacy = """
    {"llmProvider":"Apple FM 온디바이스","openAIBaseURL":"https://api.openai.com/v1",
     "openAIModel":"gpt-4o-mini","ollamaHost":"http://localhost:11434","ollamaModel":"llama3.1",
     "apiKeyAccount":"openai"}
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertEqual(s.activeProviderID, LLMProviderConfig.appleFMID)
    let remote = s.provider(LLMProviderConfig.remoteOpenAIID)
    XCTAssertEqual(remote?.baseURL, "http://192.168.86.30:8791/v1")
    XCTAssertEqual(remote?.secretID, LLMProviderConfig.remoteOpenAIID)
    XCTAssertNotEqual(s.provider(LLMProviderConfig.ollamaID)?.model, "llama3.1")
  }

  func testLegacyAppleFMStaysActive() throws {
    let legacy = #"{"llmProvider":"Apple FM 온디바이스"}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertEqual(s.activeProviderID, LLMProviderConfig.appleFMID)
    XCTAssertEqual(s.activeProvider?.type, .appleFM)
  }

  func testEncodingDropsLegacyKeys() throws {
    let legacy = #"{"llmProvider":"Ollama 로컬"}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    let json = String(data: try JSONEncoder().encode(s), encoding: .utf8)!
    XCTAssertFalse(json.contains("llmProvider"), "구버전 키는 다시 쓰지 않는다")
    XCTAssertTrue(json.contains("providers"))
  }

  func testNewProviderNamingAndSecretID() {
    var existing = LLMProviderConfig.defaultProviders()
    let created = LLMProviderConfig.newProvider(type: .openAICompatible, existing: existing)
    XCTAssertEqual(created.name, "OpenAI 호환")
    XCTAssertEqual(created.secretID, created.id, "원격 프로바이더는 개별 비밀 항목 ID를 가진다")
    existing.append(created)
    XCTAssertEqual(LLMProviderConfig.newProvider(type: .openAICompatible, existing: existing).name, "OpenAI 호환 2")
  }

  // MARK: - SecretStore (로컬 파일, 키체인 미사용)

  func testSecretStoreRoundTripInIsolatedFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qt-secret-\(UUID().uuidString)")
    SecretStore.fileURLOverride = dir.appendingPathComponent("secrets.json")
    defer {
      SecretStore.fileURLOverride = nil
      try? FileManager.default.removeItem(at: dir)
    }

    XCTAssertNil(SecretStore.load(account: "remote-openai"))
    XCTAssertTrue(SecretStore.save(account: "remote-openai", secret: "s3cret-value"))
    XCTAssertEqual(SecretStore.load(account: "remote-openai"), "s3cret-value")
    XCTAssertTrue(SecretStore.has(account: "remote-openai"))

    // 파일 권한은 소유자 전용(600)
    let attrs = try FileManager.default.attributesOfItem(atPath: SecretStore.fileURL.path)
    XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    XCTAssertTrue(SecretStore.delete(account: "remote-openai"))
    XCTAssertNil(SecretStore.load(account: "remote-openai"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: SecretStore.fileURL.path), "비어지면 파일을 남기지 않는다")
  }

  func testSecretStoreRejectsEmptyValues() {
    SecretStore.fileURLOverride = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-empty-\(UUID().uuidString).json")
    defer { SecretStore.fileURLOverride = nil }
    XCTAssertFalse(SecretStore.save(account: "x", secret: ""))
    XCTAssertFalse(SecretStore.save(account: "", secret: "y"))
    XCTAssertNil(SecretStore.load(account: ""))
  }

  func testNewWindowPositionDefaultIsCenterAndRoundTrips() throws {
    XCTAssertEqual(QuickTalkSettings().newWindowPosition, .center, "기본은 화면 중앙")
    var s = QuickTalkSettings()
    s.newWindowPosition = .mousePointer
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: try JSONEncoder().encode(s))
    XCTAssertEqual(back.newWindowPosition, .mousePointer)
    // 구버전(필드 없음) 설정도 중앙으로 폴백
    let legacy = #"{"globalShortcut":"Cmd+Space"}"#.data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(QuickTalkSettings.self, from: legacy).newWindowPosition, .center)
  }

  func testProviderTypeCapabilities() {
    XCTAssertFalse(LLMProviderType.appleFM.needsBaseURL)
    XCTAssertFalse(LLMProviderType.appleFM.needsAPIKey)
    XCTAssertFalse(LLMProviderType.appleFM.needsModel)
    XCTAssertTrue(LLMProviderType.ollama.needsBaseURL)
    XCTAssertFalse(LLMProviderType.ollama.needsAPIKey)
    XCTAssertTrue(LLMProviderType.openAICompatible.needsAPIKey)
  }

  func testErrorCodesForProviderFailures() {
    XCTAssertEqual(QuickTalkError.providerNotConfigured().code, "E-MAC-NET-0002")
    XCTAssertEqual(QuickTalkError.missingAPIKey().code, "E-MAC-KEY-0001")
  }

  /// 로컬 모델은 3~6k토큰 프롬프트의 첫 토큰이 60초를 넘는다 — 원격(60초)과 달리 300초를 기다린다.
  func testOllamaRequestTimeoutAllowsSlowLocalPrompt() {
    XCTAssertEqual(OllamaClient.requestTimeout, 300)
    XCTAssertGreaterThan(OllamaClient.requestTimeout, 60)
  }
}
