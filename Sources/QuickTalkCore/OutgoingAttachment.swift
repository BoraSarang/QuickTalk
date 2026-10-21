import Foundation
import CoreGraphics
import ImageIO
import PDFKit

/// 모델로 **실제 전송되는** 첨부 1건.
///
/// 대화 기록(`Attachment`)에는 이름·종류만 남고, 본문은 전송 순간에 이 타입으로 읽어 붙인다.
/// - 텍스트 파일 → 본문을 프롬프트에 인라인 삽입(`text`)
/// - 이미지 → `data:image/png;base64,...`(`imageDataURL`) / Ollama용 원본 base64(`imageBase64`)
///
/// 전송할 수 없거나 줄여서 보낸 경우는 `note`에 사유를 담아 **사용자에게 그대로 보여준다**(무음 실패 금지).
public struct OutgoingAttachment: Equatable {
  public var name: String
  public var kind: Attachment.Kind
  /// 텍스트 파일 본문(이미지면 nil)
  public var text: String?
  /// OpenAI 호환 비전용 `data:` URL
  public var imageDataURL: String?
  /// Ollama `images` 필드용 접두어 없는 base64
  public var imageBase64: String?
  /// 축소·잘라내기·미전송 사유(문제 없으면 nil)
  public var note: String?

  public init(name: String,
              kind: Attachment.Kind,
              text: String? = nil,
              imageDataURL: String? = nil,
              imageBase64: String? = nil,
              note: String? = nil) {
    self.name = name
    self.kind = kind
    self.text = text
    self.imageDataURL = imageDataURL
    self.imageBase64 = imageBase64
    self.note = note
  }

  /// 서버로 이미지를 실을 수 있는가
  public var hasImage: Bool { imageDataURL != nil }
  /// 서버로 텍스트 본문을 실을 수 있는가
  public var hasText: Bool { !(text ?? "").isEmpty }
}

// MARK: - 파일 → 전송용 첨부

public enum AttachmentLoader {
  /// 텍스트 파일 본문 최대 문자 수(넘으면 잘라내고 안내)
  public static let maxTextCharacters = 100_000
  /// 이미지 data URL 최대 바이트(넘으면 줄여서 다시 인코딩)
  public static let maxImageBytes = 5_000_000
  /// 원본 그대로 보내도 되는 이미지 최대 변(변을 넘으면 줄인다)
  public static let maxImageSide = 3_000

  /// 첨부 1건을 전송 가능한 형태로 읽는다. 실패해도 `note`만 담아 돌려준다(무음 실패 금지).
  public static func load(name: String, kind: Attachment.Kind, url: URL?) -> OutgoingAttachment {
    let ext = (name as NSString).pathExtension.lowercased()
    let looksImage = kind == .image || imageMime(forExtension: ext) != nil

    if looksImage {
      guard let url else {
        return OutgoingAttachment(name: name, kind: .image,
                                  note: L("이미지 파일 경로가 없어 보내지 못했습니다"))
      }
      return loadImage(name: name, url: url)
    }

    guard let url else {
      return OutgoingAttachment(name: name, kind: kind,
                                note: L("파일 경로가 없어 본문을 보내지 못했습니다(이름만 알림)"))
    }
    if ext == "pdf" { return loadPDF(name: name, url: url) }
    return loadText(name: name, kind: kind, url: url)
  }

  /// PDF → 텍스트 추출(P3). 스캔본처럼 텍스트 층이 없으면 사유를 남긴다(무음 실패 금지).
  static func loadPDF(name: String, url: URL) -> OutgoingAttachment {
    guard let doc = PDFDocument(url: url) else {
      return OutgoingAttachment(name: name, kind: .file, note: "PDF를 열 수 없습니다")
    }
    let body = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else {
      return OutgoingAttachment(name: name, kind: .file,
                                note: L("PDF에서 텍스트를 찾지 못했습니다(스캔 이미지일 수 있습니다)"))
    }
    var text = body
    var note = "PDF \(doc.pageCount)쪽에서 텍스트만 뽑아 보냈습니다"
    if text.count > maxTextCharacters {
      text = String(text.prefix(maxTextCharacters))
      note = "PDF가 커서 앞 \(maxTextCharacters)자만 보냈습니다"
    }
    return OutgoingAttachment(name: name, kind: .file, text: text, note: note)
  }

  /// 텍스트 파일 본문 읽기(UTF-8 우선, 실패 시 시스템 인코딩 추정)
  static func loadText(name: String, kind: Attachment.Kind, url: URL) -> OutgoingAttachment {
    guard var body = readText(url) else {
      return OutgoingAttachment(name: name, kind: kind,
                                note: "텍스트로 읽을 수 없어 본문을 보내지 못했습니다")
    }
    var note: String? = nil
    if body.count > maxTextCharacters {
      body = String(body.prefix(maxTextCharacters))
      note = "파일이 커서 앞 \(maxTextCharacters)자만 보냈습니다"
    }
    return OutgoingAttachment(name: name, kind: kind, text: body, note: note)
  }

  static func readText(_ url: URL) -> String? {
    if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
    var detected: NSString?
    if let data = try? Data(contentsOf: url),
       NSString.stringEncoding(for: data, encodingOptions: nil,
                               convertedString: &detected, usedLossyConversion: nil) != 0,
       let s = detected as String? {
      return s
    }
    return nil
  }

  /// 이미지 읽기 — 작으면 원본 그대로, 크면 줄여서(최대 `maxImageBytes`) 보낸다.
  static func loadImage(name: String, url: URL) -> OutgoingAttachment {
    guard let data = try? Data(contentsOf: url) else {
      return OutgoingAttachment(name: name, kind: .image, note: "파일을 읽을 수 없습니다")
    }
    let ext = url.pathExtension.lowercased()
    let directExtensions = ["png", "jpg", "jpeg", "gif", "webp"]
    let cg = cgImage(from: data)
    let side = cg.map { max($0.width, $0.height) } ?? 0

    if directExtensions.contains(ext), data.count <= maxImageBytes, side <= maxImageSide {
      let base64 = data.base64EncodedString()
      let mime = imageMime(forExtension: ext) ?? "image/png"
      return OutgoingAttachment(name: name, kind: .image,
                                imageDataURL: "data:\(mime);base64,\(base64)",
                                imageBase64: base64)
    }

    guard let source = cg else {
      return OutgoingAttachment(name: name, kind: .image,
                                note: L("이미지를 해석할 수 없습니다(지원하지 않는 형식)"))
    }
    let original = "\(source.width)×\(source.height)"
    for (maxSide, jpeg) in [(2048, false), (2048, true), (1400, true), (1024, true)] as [(CGFloat, Bool)] {
      guard let scaled = scale(source, maxSide: maxSide),
            let encoded = encode(scaled, jpeg: jpeg),
            encoded.count <= maxImageBytes else { continue }
      let base64 = encoded.base64EncodedString()
      let mime = jpeg ? "image/jpeg" : "image/png"
      return OutgoingAttachment(
        name: name, kind: .image,
        imageDataURL: "data:\(mime);base64,\(base64)",
        imageBase64: base64,
        note: "원본(\(original))이 커서 \(scaled.width)×\(scaled.height)로 줄여 보냈습니다")
    }
    return OutgoingAttachment(name: name, kind: .image,
                              note: L("이미지가 너무 커서 보내지 못했습니다"))
  }

  /// 서버가 첨부를 거부했을 때 재시도용 — 더 작게 만들어 돌려준다(실패하면 nil).
  public static func smaller(_ att: OutgoingAttachment,
                             maxSide: CGFloat = 1_400,
                             jpegQuality: CGFloat = 0.8) -> OutgoingAttachment? {
    guard att.hasImage, let base64 = att.imageBase64, let data = Data(base64Encoded: base64),
          let source = cgImage(from: data), let scaled = scale(source, maxSide: maxSide),
          let encoded = encode(scaled, jpeg: true) else { return nil }
    var out = att
    let reencoded = encoded.base64EncodedString()
    out.imageDataURL = "data:image/jpeg;base64,\(reencoded)"
    out.imageBase64 = reencoded
    out.note = "서버가 거부해 \(scaled.width)×\(scaled.height)(JPEG)로 줄여 다시 보냈습니다"
    return out
  }

  // MARK: - 이미지 유틸

  static func imageMime(forExtension ext: String) -> String? {
    switch ext.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "bmp": return "image/bmp"
    case "heic", "heif": return "image/heic"
    default: return nil
    }
  }

  static func cgImage(from data: Data) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(src) > 0 else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
  }

  static func scale(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    guard w > 0, h > 0 else { return nil }
    let factor = min(1, maxSide / max(w, h))
    let tw = max(1, Int((w * factor).rounded()))
    let th = max(1, Int((h * factor).rounded()))
    guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    return ctx.makeImage()
  }

  /// ImageIO만 쓴다(AppKit 없이 동작 — 헤드리스 테스트 가능)
  static func encode(_ image: CGImage, jpeg: Bool) -> Data? {
    let out = NSMutableData()
    let type = (jpeg ? "public.jpeg" : "public.png") as CFString
    guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
    let props: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
  }
}

// MARK: - 프롬프트 조립

public extension AttachmentLoader {
  /// 텍스트 첨부 본문을 프롬프트에 인라인으로 붙인다(모든 프로바이더 공통).
  static func composeText(prompt: String, attachments: [OutgoingAttachment]) -> String {
    let textFiles = attachments.filter { $0.hasText && !$0.hasImage }
    guard !textFiles.isEmpty else { return prompt }
    var out = prompt
    for file in textFiles {
      out += "\n\n[첨부 파일: \(file.name)]\n```\n\(file.text ?? "")\n```"
    }
    return out
  }

  /// 이번 요청에 실리는 요약 — 로그·안내용(내용 자체는 담지 않는다)
  static func summary(_ attachments: [OutgoingAttachment]) -> String {
    let images = attachments.filter { $0.hasImage }.count
    let texts = attachments.filter { $0.hasText }.count
    let failed = attachments.filter { !$0.hasImage && !$0.hasText }.count
    return Lf("이미지 %d · 텍스트 %d · 미전송 %d", images, texts, failed)
  }

  /// 사용자에게 보여줄 첨부 안내 문구(문제 없으면 빈 문자열)
  static func warnings(_ attachments: [OutgoingAttachment]) -> String {
    let lines = attachments.compactMap { att -> String? in
      guard let note = att.note else { return nil }
      return Lf("· %@: %@", att.name, note)
    }
    guard !lines.isEmpty else { return "" }
    return L("⚠️ 첨부 안내") + "\n" + lines.joined(separator: "\n") + "\n\n"
  }
}
