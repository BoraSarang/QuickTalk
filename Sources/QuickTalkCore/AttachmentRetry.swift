import Foundation

/// 첨부 전송 **재시도 사다리** (핸드오프 2026-10-20 P2).
///
/// 실패 분류(`ServerFailure`)에 따라 전략이 갈린다:
/// - 5xx·429 → 같은 요청 1회 재시도(429는 잠깐 대기)
/// - 413 → 이미지를 더 작게 만들어 재시도
/// - 400·422(이미지 포함) → 이미지를 빼고 텍스트만
/// - 401·403 → 재시도 없음(원인을 숨기지 않고 그대로 알린다)
///
/// 실패는 던지지 않고 `"(오류 <코드>) <문구>"` 문자열로 돌려준다 — 무음 실패 금지.
public enum AttachmentRetry {
  public static func send(client: any LLMClient,
                          prompt: String,
                          history: [Turn],
                          attachments: [OutgoingAttachment],
                          model: String) async throws -> String {
    guard !attachments.isEmpty else {
      return try await client.send(prompt: prompt, history: history, attachments: [])
    }
    do {
      return try await client.send(prompt: prompt, history: history, attachments: attachments)
    } catch QuickTalkError.serverFailure(let f) {
      NSLog("[WARN] %@ 서버 실패 — %@ (HTTP %d, 모델=%@)",
            f.code, f.label, f.httpStatus, model)

      // ① 일시 오류·사용 제한 — 같은 요청 1회 재시도
      if f.canRetrySameRequest {
        if f.retryDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(f.retryDelay * 1_000_000_000))
        }
        if let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: attachments) {
          return Lf("⚠️ %@ — 다시 시도해 성공했습니다.\n\n", f.userMessage) + answer
        }
      }

      let hasImage = attachments.contains { $0.hasImage }

      // ② 용량 초과 — 이미지를 더 작게
      if hasImage, f.canRetryShrunk {
        let shrunk = attachments.map { $0.hasImage ? (AttachmentLoader.smaller($0) ?? $0) : $0 }
        if shrunk != attachments,
           let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: shrunk) {
          return L("⚠️ 서버가 첨부를 거부해 이미지를 줄여 다시 보냈습니다.\n\n") + answer
        }
      }

      // ③ 모델이 이미지를 못 받는 경우 — 텍스트만 (첨부 파일 본문은 살린다)
      if hasImage, f.canRetryWithoutImage {
        let images = attachments.filter { $0.hasImage }.count
        if let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: attachments.filter { !$0.hasImage }) {
          return Lf("⚠️ 이미지 %d건은 현재 모델(%@)이 받지 못해 텍스트만 보냈습니다.\n\n", images, model) + answer
        }
      }

      return Lf("(오류 %@) %@", f.code, f.userMessage)
    }
  }

  /// 스트리밍 + 첨부 재시도.
  /// **델타가 한 글자라도 나간 뒤에는 재시도하지 않는다**(부분 출력 중복 방지).
  /// 재시도 응답은 원인 안내를 앞에 붙여야 해서 한 번에 전달한다(드문 경로).
  @MainActor
  public static func stream(client: any LLMClient,
                            prompt: String,
                            history: [Turn],
                            attachments: [OutgoingAttachment],
                            model: String,
                            onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    guard !attachments.isEmpty else {
      return try await client.stream(prompt: prompt, history: history, attachments: [], onDelta: onDelta)
    }
    var emitted = false
    let tracked: @MainActor (String) -> Void = { d in
      emitted = true
      onDelta(d)
    }
    do {
      return try await client.stream(prompt: prompt, history: history,
                                     attachments: attachments, onDelta: tracked)
    } catch QuickTalkError.serverFailure(let f) {
      NSLog("[WARN] %@ 서버 실패 — %@ (HTTP %d, 모델=%@)",
            f.code, f.label, f.httpStatus, model)
      if emitted { throw QuickTalkError.serverFailure(f) }   // 이미 보여 준 글자는 되돌리지 않는다

      // ① 일시 오류·사용 제한 — 같은 요청 1회 재시도
      if f.canRetrySameRequest {
        if f.retryDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(f.retryDelay * 1_000_000_000))
        }
        if let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: attachments) {
          let text = Lf("⚠️ %@ — 다시 시도해 성공했습니다.\n\n", f.userMessage) + answer
          tracked(text)
          return text
        }
      }

      let hasImage = attachments.contains { $0.hasImage }

      // ② 용량 초과 — 이미지를 더 작게
      if hasImage, f.canRetryShrunk {
        let shrunk = attachments.map { $0.hasImage ? (AttachmentLoader.smaller($0) ?? $0) : $0 }
        if shrunk != attachments,
           let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: shrunk) {
          let text = L("⚠️ 서버가 첨부를 거부해 이미지를 줄여 다시 보냈습니다.\n\n") + answer
          tracked(text)
          return text
        }
      }

      // ③ 모델이 이미지를 못 받는 경우 — 텍스트만 (첨부 파일 본문은 살린다)
      if hasImage, f.canRetryWithoutImage {
        let images = attachments.filter { $0.hasImage }.count
        if let answer = try? await client.send(prompt: prompt, history: history,
                                               attachments: attachments.filter { !$0.hasImage }) {
          let text = Lf("⚠️ 이미지 %d건은 현재 모델(%@)이 받지 못해 텍스트만 보냈습니다.\n\n", images, model) + answer
          tracked(text)
          return text
        }
      }

      return Lf("(오류 %@) %@", f.code, f.userMessage)
    }
  }
}
