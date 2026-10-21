import XCTest
import CoreGraphics
import ImageIO
@testable import QuickTalkCore

/// 첨부가 **모델로 실제 전송되는지** 검증한다 (버그: 이름·종류만 기록하고 내용을 보내지 않던 문제)
final class AttachmentTests: XCTestCase {

  // MARK: - 텍스트 첨부

  func testTextFileBodyIsInlinedIntoPrompt() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-attach-\(UUID().uuidString).md")
    try "# 메모\n오늘 할 일: 빌드".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .file, url: url)
    XCTAssertTrue(att.hasText, "텍스트 파일 본문을 읽어야 한다")
    XCTAssertNil(att.note)

    let composed = AttachmentLoader.composeText(prompt: "이 파일 요약해줘", attachments: [att])
    XCTAssertTrue(composed.contains("오늘 할 일: 빌드"), "본문이 프롬프트에 인라인되어야 한다")
    XCTAssertTrue(composed.hasPrefix("이 파일 요약해줘"))
  }

  func testLargeTextFileIsTruncatedWithNote() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-attach-big-\(UUID().uuidString).txt")
    let body = String(repeating: "가", count: AttachmentLoader.maxTextCharacters + 500)
    try body.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .file, url: url)
    XCTAssertEqual(att.text?.count, AttachmentLoader.maxTextCharacters)
    XCTAssertNotNil(att.note, "잘라낸 사실을 조용히 넘기면 안 된다")
    XCTAssertFalse(AttachmentLoader.warnings([att]).isEmpty)
  }

  func testMissingPathIsReportedNotSilentlyDropped() {
    let att = AttachmentLoader.load(name: "없는파일.md", kind: .file, url: nil)
    XCTAssertFalse(att.hasText)
    XCTAssertNotNil(att.note)
  }

  // MARK: - 이미지 첨부

  func testSmallImageBecomesDataURL() throws {
    let url = try writePNG(width: 64, height: 48, color: Self.red)
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .image, url: url)
    XCTAssertTrue(att.hasImage)
    XCTAssertNotNil(att.imageBase64)
    XCTAssertTrue(att.imageDataURL?.hasPrefix("data:image/png;base64,") ?? false)
    XCTAssertNil(att.note, "작은 이미지는 그대로 보낸다")
  }

  func testHugeImageIsDownscaledWithNote() throws {
    // 변 2400 초과 + 3.5MB 초과 → 줄여서 보내고 안내를 남긴다
    let url = try writePNG(width: 3000, height: 2200, color: Self.blue, noise: true)
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .image, url: url)
    XCTAssertTrue(att.hasImage, "줄여서라도 보내야 한다")
    XCTAssertNotNil(att.note)
    let encoded = Data(base64Encoded: String((att.imageBase64 ?? ""))) ?? Data()
    XCTAssertLessThanOrEqual(encoded.count, AttachmentLoader.maxImageBytes)
    if let cg = AttachmentLoader.cgImage(from: encoded) {
      XCTAssertLessThanOrEqual(max(cg.width, cg.height), 2048)
    } else {
      XCTFail("줄인 이미지를 다시 해석할 수 있어야 한다")
    }
  }

  // MARK: - 요청 본문 조립 (핵심 회귀 방지)

  func testOpenAIMessagesCarryImagePartsAndFileBody() throws {
    let imgURL = try writePNG(width: 32, height: 32, color: Self.green)
    let txtURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-attach-\(UUID().uuidString).txt")
    try "핵심 지시: 표로 답해줘".write(to: txtURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: imgURL)
      try? FileManager.default.removeItem(at: txtURL)
    }

    let atts = [
      AttachmentLoader.load(name: imgURL.lastPathComponent, kind: .image, url: imgURL),
      AttachmentLoader.load(name: txtURL.lastPathComponent, kind: .file, url: txtURL)
    ]
    let messages = OpenAIClient.buildMessages(prompt: "이 화면 뭐가 문제야?",
                                              history: [Turn(role: .user, text: "이전 질문"),
                                                        Turn(role: .assistant, text: "이전 답")],
                                              attachments: atts)

    XCTAssertEqual(messages.count, 3, "이전 2턴 + 이번 1턴")
    XCTAssertEqual(messages.last?["role"] as? String, "user")

    let parts = messages.last?["content"] as? [[String: Any]]
    XCTAssertNotNil(parts, "이미지가 있으면 content가 파트 배열이어야 한다")
    let textPart = parts?.first { $0["type"] as? String == "text" }
    let text = textPart?["text"] as? String ?? ""
    XCTAssertTrue(text.contains("이 화면 뭐가 문제야?"))
    XCTAssertTrue(text.contains("핵심 지시: 표로 답해줘"), "텍스트 파일 본문도 같이 실려야 한다")

    let imagePart = parts?.first { $0["type"] as? String == "image_url" }
    let url = ((imagePart?["image_url"] as? [String: Any])?["url"] as? String) ?? ""
    XCTAssertTrue(url.hasPrefix("data:image/png;base64,"), "이미지가 data URL로 실려야 한다")
    XCTAssertGreaterThan(url.count, 100)
  }

  func testOpenAIMessagesStayPlainTextWithoutAttachments() {
    let messages = OpenAIClient.buildMessages(prompt: "안녕", history: [], attachments: [])
    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0]["content"] as? String, "안녕", "첨부가 없으면 기존과 같은 문자열 content")
  }

  func testOllamaMessagesCarryImagesField() throws {
    let imgURL = try writePNG(width: 16, height: 16, color: Self.red)
    defer { try? FileManager.default.removeItem(at: imgURL) }
    let att = AttachmentLoader.load(name: imgURL.lastPathComponent, kind: .image, url: imgURL)

    let messages = OllamaClient.buildMessages(prompt: "뭐가 보여?", history: [], attachments: [att])
    let last = messages.last
    let images = last?["images"] as? [String]
    XCTAssertEqual(images?.count, 1)
    XCTAssertFalse(images?.first?.hasPrefix("data:") ?? true, "Ollama는 접두어 없는 base64")
  }

  func testWarningsListNotes() {
    let att = OutgoingAttachment(name: "shot.png", kind: .image, note: "너무 커서 보내지 못했습니다")
    let text = AttachmentLoader.warnings([att])
    XCTAssertTrue(text.contains("shot.png"))
    XCTAssertTrue(text.contains("너무 커서"))
  }

  // MARK: - 도우미

  private static let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
  private static let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
  private static let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

  private func writePNG(width: Int, height: Int, color: CGColor, noise: Bool = false) throws -> URL {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if noise {
      // 압축되지 않게 무작위 점을 뿌린다(큰 파일 만들기)
      var seed: UInt64 = 88172645463325252
      for _ in 0..<(width * height / 8) {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        let r = CGFloat(seed % 255) / 255, g = CGFloat((seed >> 8) % 255) / 255
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: CGFloat(seed % UInt64(width)), y: CGFloat((seed >> 16) % UInt64(height)),
                        width: 4, height: 4))
      }
    }
    let image = ctx.makeImage()!
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-attach-\(UUID().uuidString).png")
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    try (out as Data).write(to: url)
    return url
  }
}
