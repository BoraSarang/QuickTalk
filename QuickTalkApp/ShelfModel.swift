import AppKit

// [INFO] [FEATURE] QuickShelf — Edge 허브(클립보드 · 파일 · 캡처) 데이터 모델 (PLAN_v0.13)

/// QuickShelf 상단 탭
enum ShelfTab: Int, CaseIterable {
  case clipboard, files, capture

  var title: String {
    switch self {
    case .clipboard: return L("클립보드")
    case .files: return L("파일")
    case .capture: return L("캡처")
    }
  }

  var symbol: String {
    switch self {
    case .clipboard: return "doc.on.clipboard"
    case .files: return "folder"
    case .capture: return "camera.viewfinder"
    }
  }
}

/// 파일 탭에 쌓이는 항목(파일·이미지)
struct ShelfFile: Identifiable, Equatable {
  let id = UUID()
  var name: String
  var url: URL
  var kind: Attachment.Kind
  var addedAt = Date()

  var isImage: Bool { kind == .image }

  var sizeText: String? {
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }

  /// 카드용 썸네일(이미지일 때)
  var thumbnail: NSImage? {
    guard isImage else { return nil }
    return NSImage(contentsOf: url)
  }
}

/// 캡처 1건 — 원본 PNG 경로 + 표시용 축소 썸네일
struct ShelfCapture: Identifiable, Equatable {
  enum Source: String {
    case fullScreen, window, region

    var label: String {
      switch self {
      case .fullScreen: return L("전체 화면")
      case .window: return L("윈도우")
      case .region: return L("드래그")
      }
    }

    var symbol: String {
      switch self {
      case .fullScreen: return "display"
      case .window: return "macwindow"
      case .region: return "selection.pin.in.out"
      }
    }
  }

  let id = UUID()
  var url: URL
  var thumbnail: Data?
  var width: Int
  var height: Int
  var source: Source
  var createdAt = Date()

  var sizeText: String { "\(width)×\(height)" }
}

/// 호버 미리보기 대상(패널 왼쪽에 별도 창으로 뜬다)
enum ShelfPreviewTarget: Equatable {
  case clipboard(ClipboardItem, masked: Bool)
  case file(ShelfFile)
  case capture(ShelfCapture)
}
