import XCTest
import CoreGraphics
import ImageIO
@testable import QuickTalkCore

/// 살아있는 검증(임시) — 실제 엔드포인트가 이미지를 "보는지" 확인한다.
/// `QT_LIVE=1 swift test --filter LiveAttachmentCheck`
final class LiveAttachmentCheck: XCTestCase {

  func testLiveImageDelivery() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["QT_LIVE"] == "1", "QT_LIVE=1 일 때만 실행")

    let base = URL(string: "http://192.168.86.30:8791/v1")!
    let secretsPath = NSHomeDirectory() + "/Library/Application Support/QuickTalk/secrets.json"
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: secretsPath)))
    let secrets = json as? [String: String] ?? [:]
    let key = secrets["remote-openai"] ?? secrets.values.first ?? ""
    XCTAssertFalse(key.isEmpty, "토큰 필요")

    // 왼쪽 절반 = 빨강, 오른쪽 절반 = 파랑
    let w = 512, h = 256
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
    let image = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qt-live-half.png")
    try (out as Data).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let att = AttachmentLoader.load(name: "half.png", kind: .image, url: url)
    print("[LIVE] 첨부 요약: \(AttachmentLoader.summary([att])), note=\(att.note ?? "없음")")
    XCTAssertTrue(att.hasImage)

    // 앱과 같은 경로로 메시지 조립 → 그대로 전송
    let messages = OpenAIClient.buildMessages(
      prompt: "이 이미지 왼쪽 절반과 오른쪽 절반의 색을 한국어로 각각 한 단어로만 답해줘. 형식: 왼쪽=?, 오른쪽=?",
      history: [], attachments: [att])
    print("[LIVE] content 파트 수: \((messages.last?["content"] as? [[String: Any]])?.count ?? -1)")

    let client = OpenAIClient(baseURL: base, apiKey: key, model: "deepseek-v4.1-flash-free")
    let reply = try await client.send(prompt: "이 이미지 왼쪽 절반과 오른쪽 절반의 색을 한국어로 각각 한 단어로만 답해줘. 형식: 왼쪽=?, 오른쪽=?",
                                      history: [], attachments: [att])
    print("[LIVE] 모델 응답: \(reply)")
    let answer = reply.replacingOccurrences(of: " ", with: "")
    XCTAssertTrue(answer.contains("빨강") || answer.contains("빨간") || answer.contains("적색"),
                  "왼쪽(빨강)을 못 봤다: \(reply)")
    XCTAssertTrue(answer.contains("파랑") || answer.contains("파란") || answer.contains("청색"),
                  "오른쪽(파랑)을 못 봤다: \(reply)")
  }

  /// 레티나 전체화면급 큰 이미지(노이즈 포함) — 줄여서 보내도 모델이 보는지 확인
  func testLiveLargeImageDelivery() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["QT_LIVE"] == "1", "QT_LIVE=1 일 때만 실행")
    let base = URL(string: "http://192.168.86.30:8791/v1")!
    let secretsPath = NSHomeDirectory() + "/Library/Application Support/QuickTalk/secrets.json"
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: secretsPath)))
    let key = (json as? [String: String])?["remote-openai"] ?? ((json as? [String: String])?.values.first ?? "")
    XCTAssertFalse(key.isEmpty, "토큰 필요")

    let w = 3024, h = 1964                     // 16인치 레티나 전체화면과 비슷한 크기
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var seed: UInt64 = 12345678901234567
    for _ in 0..<(w * h / 6) {
      seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
      let x = CGFloat(seed % UInt64(w)), y = CGFloat((seed >> 16) % UInt64(h))
      let left = x < CGFloat(w / 2)
      let r = left ? CGFloat(200 + seed % 55) / 255 : CGFloat(seed % 40) / 255
      let b = left ? CGFloat(seed % 40) / 255 : CGFloat(200 + seed % 55) / 255
      ctx.setFillColor(CGColor(srgbRed: r, green: CGFloat((seed >> 8) % 60) / 255, blue: b, alpha: 1))
      ctx.fill(CGRect(x: x, y: y, width: 6, height: 6))
    }
    let image = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qt-live-big.png")
    try (out as Data).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    print("[LIVE] 원본 PNG: \(out.length / 1_048_576)MB (\(w)×\(h))")

    let att = AttachmentLoader.load(name: "big.png", kind: .image, url: url)
    print("[LIVE] 전송 크기: \((att.imageBase64?.count ?? 0) / 1_048_576)MB, note=\(att.note ?? "없음")")
    XCTAssertTrue(att.hasImage)

    let client = OpenAIClient(baseURL: base, apiKey: key, model: "deepseek-v4.1-flash-free")
    let reply = try await client.send(prompt: "이 이미지에서 왼쪽 절반과 오른쪽 절반은 각각 무슨 색 계열인가요? 한국어 한 단어씩. 형식: 왼쪽=?, 오른쪽=?",
                                      history: [], attachments: [att])
    print("[LIVE] 큰 이미지 모델 응답: \(reply)")
    XCTAssertTrue(reply.contains("빨") || reply.contains("적"), "왼쪽(빨강 계열)을 못 봤다: \(reply)")
    XCTAssertTrue(reply.contains("파") || reply.contains("청"), "오른쪽(파랑 계열)을 못 봤다: \(reply)")
  }

  /// P2 실측 — **잘못된 토큰**이 "이미지 거부"가 아니라 키 거부(E-MAC-KEY-0002)로 분류되는지.
  /// (프록시는 401 + `E-AND-AUTH-0004`를 준다 — 분류기가 본문 코드를 읽어야 맞힌다)
  func testLiveWrongTokenIsClassifiedAsKeyRejection() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["QT_LIVE"] == "1", "QT_LIVE=1 일 때만 실행")
    let base = URL(string: "http://192.168.86.30:8791/v1")!
    let client = OpenAIClient(baseURL: base, apiKey: "zfp_00000000000000000000000000000000",
                              model: "deepseek-v4.1-flash-free")
    do {
      _ = try await client.send(prompt: "확인", history: [], attachments: [])
      XCTFail("잘못된 토큰인데 성공했다 — 프록시 외부 공유 설정을 확인해야 한다")
    } catch QuickTalkError.serverFailure(let f) {
      print("[LIVE] 잘못된 토큰 분류: code=\(f.code) HTTP=\(f.httpStatus) 서버코드=\(f.serverCode ?? "없음")")
      XCTAssertEqual(f.code, "E-MAC-KEY-0002", "401은 키 거부로 분류돼야 한다")
      XCTAssertFalse(f.canRetryWithoutImage, "키 거부로 이미지를 빼고 재시도하면 안 된다")
    }
  }
}
