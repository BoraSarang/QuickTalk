import XCTest
@testable import QuickTalkCore

final class ProviderResolverTests: XCTestCase {
  private func settings() -> QuickTalkSettings {
    var s = QuickTalkSettings()
    s.providers = [
      LLMProviderConfig(id: "a", name: "A", type: .openAICompatible,
                        baseURL: "http://a/v1", model: "a-model", enabled: true),
      LLMProviderConfig(id: "b", name: "B", type: .openAICompatible,
                        baseURL: "http://b/v1", model: "b-model", enabled: true),
      LLMProviderConfig(id: "off", name: "Off", type: .openAICompatible,
                        baseURL: "http://off/v1", model: "off-model", enabled: false)
    ]
    s.activeProviderID = "a"
    return s
  }

  func testNoPersonaUsesActiveProvider() {
    let r = ProviderResolver.resolve(settings: settings(), persona: nil)
    XCTAssertEqual(r.provider?.id, "a")
    XCTAssertNil(r.fallback)
  }

  func testPersonaProviderOverridesProviderAndModel() {
    let persona = Persona(name: "코딩", providerID: "b", model: "coding-model")
    let r = ProviderResolver.resolve(settings: settings(), persona: persona)
    XCTAssertEqual(r.provider?.id, "b")
    XCTAssertEqual(r.provider?.model, "coding-model")
    XCTAssertNil(r.fallback)
  }

  func testPersonaProviderKeepsProviderModelWhenModelEmpty() {
    let persona = Persona(name: "코딩", providerID: "b")
    let r = ProviderResolver.resolve(settings: settings(), persona: persona)
    XCTAssertEqual(r.provider?.id, "b")
    XCTAssertEqual(r.provider?.model, "b-model")
  }

  func testPersonaModelOnlyOverridesActiveModel() {
    let persona = Persona(name: "코딩", model: "coding-model")
    let r = ProviderResolver.resolve(settings: settings(), persona: persona)
    XCTAssertEqual(r.provider?.id, "a")
    XCTAssertEqual(r.provider?.model, "coding-model")
  }

  func testDisabledProviderFallsBackToActiveWithoutModelOverride() {
    let persona = Persona(name: "코딩", providerID: "off", model: "coding-model")
    let r = ProviderResolver.resolve(settings: settings(), persona: persona)
    XCTAssertEqual(r.provider?.id, "a")
    XCTAssertEqual(r.provider?.model, "a-model")
    XCTAssertEqual(r.fallback, .providerDisabled)
    XCTAssertNotNil(r.warning)
  }

  func testMissingProviderFallsBackToActive() {
    let persona = Persona(name: "코딩", providerID: "gone")
    let r = ProviderResolver.resolve(settings: settings(), persona: persona)
    XCTAssertEqual(r.provider?.id, "a")
    XCTAssertEqual(r.fallback, .providerMissing)
  }

  func testPersonaIDLookupMatchesObjectLookup() {
    var s = settings()
    let persona = Persona(name: "코딩", providerID: "b", model: "m")
    s.personas = [persona]
    let byID = ProviderResolver.resolve(settings: s, personaID: persona.id)
    XCTAssertEqual(byID.provider?.id, "b")
    XCTAssertEqual(byID.provider?.model, "m")
  }
}
