import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum AppleFMError: Error, LocalizedError {
  case unsupportedOS
  case unavailable(String)
  public var errorDescription: String? {
    switch self {
    case .unsupportedOS: return L("Apple FM은 macOS 26+ 필요")
    case .unavailable(let r): return Lf("Apple FM 사용 불가: %@", r)
    }
  }
}

/// Apple Intelligence 온디바이스 모델 상태 (설정 UI 표시용)
public func appleFMAvailability() -> String {
  #if canImport(FoundationModels)
  if #available(macOS 26.0, *) {
    switch SystemLanguageModel.default.availability {
    case .available: return L("사용 가능")
    case .unavailable(let reason): return Lf("사용 불가 (%@)", String(describing: reason))
    }
  } else {
    return L("macOS 26+ 필요")
  }
  #else
  return L("지원 안 됨")
  #endif
}

public func appleFMReply(prompt: String,
                         history: [Turn],
                         attachments: [OutgoingAttachment] = []) async throws -> String {
  // Apple FM은 이미지를 받지 않는다 — 텍스트 파일 본문만 인라인해서 보낸다
  let prompt = AttachmentLoader.composeText(prompt: prompt, attachments: attachments)
  #if canImport(FoundationModels)
  if #available(macOS 26.0, *) {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available: break
    case .unavailable(let reason):
      throw AppleFMError.unavailable(String(describing: reason))
    }
    // 직전 6턴만 컨텍스트로 포함 (토큰 절약)
    let ctx = history.suffix(6).map { t in
      (t.role == .user ? "사용자: " : "어시스턴트: ") + t.text
    }.joined(separator: "\n")
    let full = ctx.isEmpty ? prompt : "이전 대화:\n\(ctx)\n\n새 질문: \(prompt)"
    let session = LanguageModelSession(instructions: L("간결한 한국어 어시스턴트. 짧게 답한다."))
    let res = try await session.respond(to: full)
    return res.content
  } else {
    throw AppleFMError.unsupportedOS
  }
  #else
  throw AppleFMError.unsupportedOS
  #endif
}
