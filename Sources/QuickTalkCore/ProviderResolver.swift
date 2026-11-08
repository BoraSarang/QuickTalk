import Foundation

/// 이 대화가 실제로 쓸 AI를 **한 곳에서** 정한다.
///
/// v0.27까지 `Persona.providerID/model`은 예약 실행에만 적용됐다. v0.35부터는
/// 일반 대화·대화 정리·후속 질문·웹 판정이 모두 같은 해석을 쓴다 — 토큰 예산과
/// 실제 호출 모델이 어긋나지 않게 하기 위해서다.
///
/// 우선순위
/// 1. 비서가 지정한 프로바이더가 있고 켜져 있음 → 그 프로바이더 (+ 비서 모델 덮어쓰기)
/// 2. 비서에 모델만 있음 → 설정의 활성 프로바이더 (+ 비서 모델)
/// 3. 그 외 → 설정의 활성 프로바이더
///
/// 비서가 지정한 프로바이더가 **없거나 꺼져 있으면** 활성 AI로 폴백하고 이유를 남긴다.
/// 이때 비서 모델은 적용하지 않는다 — 다른 프로바이더에 없는 모델일 수 있다.
public struct ProviderResolution: Equatable {
  public enum Fallback: Equatable, Sendable {
    /// 비서가 가리킨 프로바이더 ID가 설정에 없다.
    case providerMissing
    /// 비서가 가리킨 프로바이더가 꺼져 있다.
    case providerDisabled
  }

  public let provider: LLMProviderConfig?
  public let fallback: Fallback?

  public init(provider: LLMProviderConfig?, fallback: Fallback? = nil) {
    self.provider = provider
    self.fallback = fallback
  }

  /// 화면에 보여 줄 경고 — 폴백이 없으면 nil.
  public var warning: String? {
    switch fallback {
    case .providerMissing, .providerDisabled:
      return L("지정한 AI가 꺼져 있어 설정의 활성 AI로 동작합니다.")
    case nil:
      return nil
    }
  }
}

public enum ProviderResolver {
  /// ID로 비서를 찾아 해석한다(대화의 `personaID` 경로).
  public static func resolve(settings: QuickTalkSettings,
                             personaID: UUID?) -> ProviderResolution {
    resolve(settings: settings, persona: settings.persona(personaID))
  }

  public static func resolve(settings: QuickTalkSettings,
                             persona: Persona?) -> ProviderResolution {
    let active = settings.activeProvider
    guard let persona = persona?.normalized() else {
      return ProviderResolution(provider: active)
    }

    // 1) 프로바이더 지정 — 있으면 그 프로바이더를 쓴다.
    if let id = persona.providerID {
      guard let chosen = settings.provider(id) else {
        return ProviderResolution(provider: active, fallback: .providerMissing)
      }
      guard chosen.enabled else {
        return ProviderResolution(provider: active, fallback: .providerDisabled)
      }
      var provider = chosen
      if let model = persona.model, !model.isEmpty { provider.model = model }
      return ProviderResolution(provider: provider)
    }

    // 2) 모델만 지정 — 활성 프로바이더의 모델만 덮어쓴다.
    guard var provider = active else {
      return ProviderResolution(provider: nil)
    }
    if let model = persona.model, !model.isEmpty { provider.model = model }
    return ProviderResolution(provider: provider)
  }

  /// 편의 — 경고가 필요 없는 곳(전송 경로)에서 바로 쓴다.
  public static func provider(settings: QuickTalkSettings,
                              persona: Persona?) -> LLMProviderConfig? {
    resolve(settings: settings, persona: persona).provider
  }

  public static func provider(settings: QuickTalkSettings,
                              personaID: UUID?) -> LLMProviderConfig? {
    resolve(settings: settings, personaID: personaID).provider
  }
}
