import SwiftUI
import ImageIO

/// 첨부 미리보기 모델 — **입력 전(PendingAttachment)과 전송 후(Attachment)를 같은 카드로** 보여준다.
/// (사용자 요청: 보낸 메시지에도 무엇을 첨부했는지 썸네일 + 동일한 호버 미리보기)
struct AttachmentPreview: Equatable {
  var name: String
  var kind: Attachment.Kind
  var image: NSImage?
  /// 크기·해상도 문구(예: `930×432 · 74KB`)
  var detail: String?
  /// 원본 경로 표시용
  var pathText: String?
  /// 문제 안내(파일이 지워짐 등)
  var note: String?
  var footer: String?

  // MARK: - 전송 후(대화 기록)

  static func sent(_ a: Attachment) -> AttachmentPreview {
    var detail: String?
    var note: String?
    var image: NSImage?
    var pathText: String?
    let fm = FileManager.default
    if let path = a.path {
      let url = URL(fileURLWithPath: path)
      pathText = url.deletingLastPathComponent().path
      if fm.fileExists(atPath: path) {
        let sizeText = (try? fm.attributesOfItem(atPath: path))?[.size]
          .flatMap { ($0 as? NSNumber)?.int64Value }
          .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if a.kind == .image {
          image = AttachmentThumbCache.shared.thumbnail(path: path, maxSide: 480)
          let pixels = AttachmentThumbCache.shared.pixelSize(path: path)
          detail = [pixels.map { "\(Int($0.width))×\(Int($0.height))" }, sizeText]
            .compactMap { $0 }.joined(separator: " · ")
          if image == nil { note = L("이미지를 읽을 수 없습니다") }
        } else {
          detail = sizeText
        }
      } else {
        note = L("원본 파일이 없습니다(지워졌거나 이동됨)")
      }
    } else {
      note = L("파일 경로가 기록되지 않은 첨부입니다")
    }
    return AttachmentPreview(name: a.name, kind: a.kind, image: image,
                             detail: detail?.isEmpty == true ? nil : detail,
                             pathText: pathText, note: note,
                             footer: L("이 메시지와 함께 전송됨"))
  }

  // MARK: - 입력 전(보내기 전 칩)

  static func pending(_ p: PendingAttachment) -> AttachmentPreview {
    var detail = p.sizeText
    if p.kind == .image, let url = p.url,
       let pixels = AttachmentThumbCache.shared.pixelSize(path: url.path) {
      detail = [ "\(Int(pixels.width))×\(Int(pixels.height))", p.sizeText]
        .compactMap { $0 }.joined(separator: " · ")
    }
    var note: String?
    if p.url == nil, p.kind != .image { note = L("클립보드 파일명만 있는 첨부입니다(전송 시 이름만 전달)") }
    return AttachmentPreview(name: p.name, kind: p.kind, image: p.image,
                             detail: detail, pathText: p.url?.deletingLastPathComponent().path,
                             note: note,
                             footer: L("전송 시 함께 전달됩니다 · ✕로 제거할 수 있습니다"))
  }
}

/// 첨부 썸네일 캐시 — 말풍선을 그릴 때마다 큰 PNG를 다시 디코딩하지 않게 한다.
/// (원본이 지워지면 캐시에서도 잊어야 하므로 존재 확인은 호출부에서 한다)
final class AttachmentThumbCache {
  static let shared = AttachmentThumbCache()

  private var thumbs: [String: NSImage] = [:]
  private var pixelSizes: [String: CGSize] = [:]

  /// 축소 썸네일(원본이 작으면 그대로)
  func thumbnail(path: String, maxSide: CGFloat) -> NSImage? {
    let key = "\(path)#\(Int(maxSide))"
    if let hit = thumbs[key] { return hit }
    guard let source = NSImage(contentsOfFile: path) else { return nil }
    let size = source.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = NSSize(width: max(1, (size.width * scale).rounded()),
                        height: max(1, (size.height * scale).rounded()))
    let out = NSImage(size: target)
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(origin: .zero, size: target),
                from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    out.unlockFocus()
    thumbs[key] = out
    return out
  }

  /// 픽셀 크기(헤더만 읽는다 — 디코딩 없음)
  func pixelSize(path: String) -> CGSize? {
    if let hit = pixelSizes[path] { return hit }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    let size = CGSize(width: width, height: height)
    pixelSizes[path] = size
    return size
  }
}
