import XCTest
import CoreGraphics
import CoreText
@testable import QuickTalkCore

/// 핸드오프(2026-10-20) P1~P3 회귀 방지:
/// P1 클립보드 파일 URL 보존 · P2 상태코드별 실패 분류 · P3 지원 형식 확대(PDF 포함)
final class AttachmentHandoffTests: XCTestCase {

  // MARK: - P1: 클립보드 파일은 경로를 보존해야 본문이 전송된다

  func testClipboardFileItemKeepsURLAndLoaderReadsBody() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-clip-\(UUID().uuidString).md")
    try "# 핸드오프\nP1: 클립보드 파일 본문".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let item = ClipboardItem(kind: .file, text: url.lastPathComponent, fileURL: url)
    XCTAssertEqual(item.fileURL, url, "클립보드는 파일 위치를 보관해야 한다")

    let att = AttachmentLoader.load(name: item.text, kind: .file, url: item.fileURL)
    XCTAssertTrue(att.hasText, "경로가 있으면 본문을 읽어야 한다")
    XCTAssertNil(att.note, "경로가 있으므로 '이름만' 안내가 붙으면 안 된다")
    XCTAssertTrue(att.text?.contains("P1: 클립보드 파일 본문") ?? false)
  }

  func testClipboardItemWithoutURLKeepsBackwardCompatibleDefaults() {
    let item = ClipboardItem(kind: .file, text: "x.md")
    XCTAssertNil(item.fileURL)
    XCTAssertFalse(item.isSensitive)
  }

  // MARK: - P2: 실패 분류

  func testClassificationCoversStatusCodes() {
    XCTAssertEqual(ServerFailure.classify(status: 401, body: "", hasImage: false)?.code, "E-MAC-KEY-0002")
    XCTAssertEqual(ServerFailure.classify(status: 403, body: "", hasImage: false)?.code, "E-MAC-KEY-0002")
    XCTAssertEqual(ServerFailure.classify(status: 413, body: "", hasImage: true)?.code, "E-MAC-ATT-0002")
    XCTAssertEqual(ServerFailure.classify(status: 429, body: "", hasImage: true)?.code, "E-MAC-NET-0004")
    XCTAssertEqual(ServerFailure.classify(status: 500, body: "", hasImage: false)?.code, "E-MAC-NET-0003")
    XCTAssertEqual(ServerFailure.classify(status: 503, body: "", hasImage: true)?.code, "E-MAC-NET-0003")
    XCTAssertNil(ServerFailure.classify(status: 200, body: "{}", hasImage: true))
    // 400/422는 **이미지가 실렸을 때만** 모델 능력 문제로 본다
    let withImage = ServerFailure.classify(status: 400, body: "", hasImage: true)
    XCTAssertEqual(withImage?.code, "E-MAC-ATT-0003")
    XCTAssertTrue(withImage?.canRetryWithoutImage ?? false)
    XCTAssertEqual(ServerFailure.classify(status: 422, body: "", hasImage: true)?.code, "E-MAC-ATT-0003")
    XCTAssertEqual(ServerFailure.classify(status: 400, body: "", hasImage: false)?.code, "E-MAC-NET-0005")
    XCTAssertEqual(ServerFailure.classify(status: 404, body: "", hasImage: true)?.code, "E-MAC-NET-0005")
    XCTAssertEqual(ServerFailure.classify(status: 426, body: "", hasImage: true)?.code, "E-MAC-NET-0005")
  }

  func testRetryStrategyPerClassification() {
    XCTAssertTrue(ServerFailure.attachmentTooLarge(status: 413, code: nil).canRetryShrunk)
    XCTAssertFalse(ServerFailure.attachmentTooLarge(status: 413, code: nil).canRetryWithoutImage)
    XCTAssertTrue(ServerFailure.upstream(status: 502, code: nil).canRetrySameRequest)
    XCTAssertTrue(ServerFailure.rateLimited(status: 429, code: nil).canRetrySameRequest)
    XCTAssertGreaterThan(ServerFailure.rateLimited(status: 429, code: nil).retryDelay, 0)
    XCTAssertFalse(ServerFailure.keyRejected(status: 401, code: nil).canRetrySameRequest)
    XCTAssertFalse(ServerFailure.keyRejected(status: 401, code: nil).canRetryWithoutImage)
    XCTAssertFalse(ServerFailure.requestRejected(status: 404, code: nil).canRetrySameRequest)
  }

  func testProxyAuthCodeWinsOverStatusCode() {
    // 프록시가 인증 실패를 400으로 감싸 보내도 코드(E-AND-AUTH-0004)로 401처럼 분류한다
    let body = #"{"type":"error","error":{"type":"unauthorized","code":"E-AND-AUTH-0004","message":"invalid token"}}"#
    let failure = ServerFailure.classify(status: 400, body: body, hasImage: true)
    XCTAssertEqual(failure?.code, "E-MAC-KEY-0002")
    XCTAssertEqual(failure?.serverCode, "E-AND-AUTH-0004")
  }

  func testServerCodeParsingAcceptsNestedAndFlatShapes() {
    XCTAssertEqual(ServerFailure.serverCode(inBody: #"{"error":{"code":"E-AND-RATE-0002"}}"#),
                   "E-AND-RATE-0002")
    XCTAssertEqual(ServerFailure.serverCode(inBody: #"{"code":"E-AND-UP-0001"}"#), "E-AND-UP-0001")
    XCTAssertNil(ServerFailure.serverCode(inBody: "not json"))
    XCTAssertNil(ServerFailure.serverCode(inBody: #"{"error":{"message":"한글 메시지"}}"#))
  }

  func testUserMessageDoesNotLeakResponseBody() {
    let secretish = "sk-live-abc123 프롬프트 원문 노출 금지"
    let body = #"{"type":"error","error":{"type":"server_error","message":"\#(secretish)"}}"#
    let failure = ServerFailure.classify(status: 500, body: body, hasImage: true)!
    let message = "(오류 \(failure.code)) \(failure.userMessage)"
    XCTAssertFalse(message.contains("sk-live"), "서버 본문은 사용자 문구로 새지 않는다")
    XCTAssertFalse(message.contains("프롬프트 원문"))
    XCTAssertTrue(message.contains("E-MAC-NET-0003"))
  }

  func testQuickTalkErrorCarriesClassificationCode() {
    XCTAssertEqual(QuickTalkError.serverFailure(.attachmentTooLarge(status: 413, code: nil)).code,
                   "E-MAC-ATT-0002")
    XCTAssertEqual(QuickTalkError.serverFailure(.keyRejected(status: 401, code: nil)).code,
                   "E-MAC-KEY-0002")
    XCTAssertTrue(QuickTalkError.serverFailure(.upstream(status: 500, code: nil))
      .userText?.contains("E-MAC-NET-0003") ?? false)
    XCTAssertNil(QuickTalkError.networkUnavailable().userText, "기존 코드 문구는 그대로 둔다")
  }

  // MARK: - P2: 재시도 사다리

  func testLadderDropsImagesOnUnsupportedAttachment() async throws {
    let image = try smallImage()
    let text = OutgoingAttachment(name: "note.md", kind: .file, text: "본문")
    let client = ScriptedClient([
      .failure(QuickTalkError.serverFailure(
        .attachmentUnsupported(status: 400, code: "E-AND-REQ-0001"))),
      .success("텍스트만으로 답변")
    ])

    let answer = try await AttachmentRetry.send(client: client, prompt: "봐줘", history: [],
                                                attachments: [image, text], model: "m")
    XCTAssertTrue(answer.contains("텍스트만 보냈습니다"), answer)
    XCTAssertEqual(client.calls.count, 2)
    XCTAssertFalse(client.calls[1].contains { $0.hasImage }, "2차는 이미지를 빼야 한다")
    XCTAssertTrue(client.calls[1].contains { $0.hasText }, "파일 본문은 살린다")
  }

  func testLadderShrinksImageOnTooLarge() async throws {
    let image = try smallImage(side: 900)
    let client = ScriptedClient([
      .failure(QuickTalkError.serverFailure(.attachmentTooLarge(status: 413, code: nil))),
      .success("줄인 이미지로 답변")
    ])

    let answer = try await AttachmentRetry.send(client: client, prompt: "봐줘", history: [],
                                                attachments: [image], model: "m")
    XCTAssertTrue(answer.contains("줄여 다시 보냈습니다"), answer)
    XCTAssertEqual(client.calls.count, 2)
    XCTAssertTrue(client.calls[1].first?.hasImage ?? false)
    XCTAssertNotEqual(client.calls[1].first?.imageBase64, image.imageBase64, "더 작게 다시 인코딩해야 한다")
  }

  func testLadderRetriesOnceOnUpstreamError() async throws {
    let image = try smallImage()
    let client = ScriptedClient([
      .failure(QuickTalkError.serverFailure(.upstream(status: 502, code: nil))),
      .success("재시도 성공")
    ])
    let answer = try await AttachmentRetry.send(client: client, prompt: "봐줘", history: [],
                                                attachments: [image], model: "m")
    XCTAssertTrue(answer.contains("다시 시도해 성공했습니다"), answer)
    XCTAssertEqual(client.calls.count, 2)
  }

  func testLadderDoesNotRetryKeyRejection() async throws {
    let image = try smallImage()
    let client = ScriptedClient([
      .failure(QuickTalkError.serverFailure(.keyRejected(status: 401, code: "E-AND-AUTH-0004")))
    ])
    let answer = try await AttachmentRetry.send(client: client, prompt: "봐줘", history: [],
                                                attachments: [image], model: "m")
    XCTAssertTrue(answer.hasPrefix("(오류 E-MAC-KEY-0002)"), answer)
    XCTAssertTrue(answer.contains("E-AND-AUTH-0004"), "서버 코드는 진단용으로 남긴다")
    XCTAssertEqual(client.calls.count, 1, "키 거부는 재시도하지 않는다")
  }

  func testLadderPassesThroughSuccessWithoutRetry() async throws {
    let image = try smallImage()
    let client = ScriptedClient([.success("바로 성공")])
    let answer = try await AttachmentRetry.send(client: client, prompt: "봐줘", history: [],
                                                attachments: [image], model: "m")
    XCTAssertEqual(answer, "바로 성공")
    XCTAssertEqual(client.calls.count, 1)
  }

  func testEmptyResponseIsNotReportedAsNetworkError() {
    XCTAssertEqual(ServerFailure.emptyResponse(status: 200).code, "E-MAC-NET-0003")
    XCTAssertTrue(ServerFailure.emptyResponse(status: 200).userMessage.contains("빈 응답"))
  }

  // MARK: - P3: 지원 형식 확대 + PDF 본문 추출

  func testSupportedFormatsAreWiderButStillBounded() {
    for name in ["a.md", "b.txt", "c.json", "d.swift", "e.csv", "f.yml", "g.log", "h.py", "i.pdf"] {
      XCTAssertTrue(Attachment.isSupported(filename: name), "\(name)은 첨부 가능해야 한다")
    }
    for name in ["x.docx", "y.exe", "z.zip", "w.dmg"] {
      XCTAssertFalse(Attachment.isSupported(filename: name), "\(name)은 아직 지원하지 않는다")
    }
    XCTAssertTrue(Attachment.isImageName("shot.PNG"))
    XCTAssertFalse(Attachment.isImageName("note.md"))
  }

  func testPDFTextIsExtractedIntoPrompt() throws {
    let url = try writePDF(text: "QuickTalk PDF 첨부 확인")
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .file, url: url)
    XCTAssertTrue(att.hasText, "PDF 텍스트 층을 읽어야 한다")
    XCTAssertNotNil(att.note, "PDF는 '텍스트만 뽑았다'고 알린다")
    XCTAssertTrue(att.text?.contains("PDF") ?? false, "본문: \(att.text ?? "nil")")

    let composed = AttachmentLoader.composeText(prompt: "요약해줘", attachments: [att])
    XCTAssertTrue(composed.contains("[첨부 파일:"))
  }

  func testEmptyPDFReportsReasonInsteadOfSilence() throws {
    let url = try writePDF(text: "")     // 텍스트 층 없는 PDF
    defer { try? FileManager.default.removeItem(at: url) }
    let att = AttachmentLoader.load(name: url.lastPathComponent, kind: .file, url: url)
    XCTAssertFalse(att.hasText)
    XCTAssertNotNil(att.note, "빈 PDF도 사유를 남긴다")
  }

  // MARK: - 전송 후 말풍선용 경로 보존

  func testAttachmentPathRoundTripsAndLegacyJSONDecodes() throws {
    let att = Attachment(name: "shot.png", kind: .image, path: "/tmp/shot.png")
    let back = try JSONDecoder().decode(Attachment.self,
                                       from: try JSONEncoder().encode(att))
    XCTAssertEqual(back.path, "/tmp/shot.png")

    let legacy = #"{"name":"note.md","kind":"file"}"#.data(using: .utf8)!
    let old = try JSONDecoder().decode(Attachment.self, from: legacy)
    XCTAssertNil(old.path, "경로가 없던 예전 기록도 읽혀야 한다")
  }

  // MARK: - 도우미

  private final class ScriptedClient: LLMClient {
    private var script: [Result<String, Error>]
    private(set) var calls: [[OutgoingAttachment]] = []
    init(_ script: [Result<String, Error>]) { self.script = script }
    func send(prompt: String, history: [Turn],
              attachments: [OutgoingAttachment]) async throws -> String {
      calls.append(attachments)
      guard !script.isEmpty else { return "(스크립트 끝)" }
      switch script.removeFirst() {
      case .success(let s): return s
      case .failure(let e): throw e
      }
    }
  }

  private func smallImage(side: Int = 24) throws -> OutgoingAttachment {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let image = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    let data = out as Data
    return OutgoingAttachment(name: "shot.png", kind: .image,
                              imageDataURL: "data:image/png;base64,\(data.base64EncodedString())",
                              imageBase64: data.base64EncodedString())
  }

  private func writePDF(text: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-pdf-\(UUID().uuidString).pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
      throw XCTSkip("PDF 컨텍스트를 만들 수 없습니다")
    }
    ctx.beginPDFPage(nil)
    if !text.isEmpty {
      let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
      let attributed = NSAttributedString(
        string: text,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
      let line = CTLineCreateWithAttributedString(attributed)
      ctx.textPosition = CGPoint(x: 72, y: 700)
      CTLineDraw(line, ctx)
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return url
  }
}
