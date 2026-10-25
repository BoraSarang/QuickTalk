import Foundation
import CoreGraphics

// [INFO] [FEATURE] 창 연결 — 창 하나의 텍스트(접근성)와 스크린샷을 질문 컨텍스트로 첨부한다 (P0-1)
//
// Meta AI for macOS의 "창 연결"(Window attachment)과 같은 목적이지만 **읽기 전용**이다.
//   - 창 조작(컴퓨터 유즈)은 넣지 않는다. 모델에는 "다시 읽을 수 없는 단일 스냅샷"이라고 알린다.
//   - 첨부는 기존 첨부 파이프라인(텍스트 파일 + 이미지)을 그대로 쓴다 → 프로바이더 3종 모두 동작한다.
//   - 서버 업로드는 하지 않는다(QuickTalk 원칙). 텍스트·이미지는 요청에 실려 모델로만 간다.

/// 창 연결 대상 1개 — 화면에 보이는 일반 창.
public struct WindowTarget: Identifiable, Equatable {
  /// `CGWindowID`(창 번호)
  public let id: CGWindowID
  /// 소유 프로세스
  public let pid: pid_t
  public let bundleID: String
  /// 앱 이름(예: `Safari`)
  public let appName: String
  /// 창 제목(없을 수 있다)
  public let title: String
  public let width: CGFloat
  public let height: CGFloat

  public init(id: CGWindowID, pid: pid_t, bundleID: String, appName: String,
              title: String, width: CGFloat, height: CGFloat) {
    self.id = id
    self.pid = pid
    self.bundleID = bundleID
    self.appName = appName
    self.title = title
    self.width = width
    self.height = height
  }

  /// 목록·칩에 보여줄 이름 — 제목이 없으면 앱 이름
  public var displayTitle: String {
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? appName : t
  }
}

/// 창 연결 규칙 — 순수 계산만 담는다(테스트 가능).
public enum WindowContextLimits {
  /// 첨부하는 창 텍스트 최대 문자 수(넘으면 줄 경계에서 자른다)
  public static let maxTextCharacters = 20_000
  /// 접근성 트리 순회 상한 — 앱이 거대해도 UI를 붙잡지 않게
  public static let maxNodes = 4_000
  public static let maxDepth = 40
  /// 창으로 치지 않는 최소 크기
  public static let minWidth: CGFloat = 80
  public static let minHeight: CGFloat = 60

  /// 시스템 UI — 창 목록에서 제외한다(사용자가 고를 이유가 없고, 읽어도 의미가 없다).
  public static let excludedBundleIDs: Set<String> = [
    "com.apple.controlcenter",
    "com.apple.systemuiserver",
    "com.apple.WindowManager",
    "com.apple.notificationcenterui",
    "com.apple.wallpaper",
    "com.apple.Spotlight",
    "com.apple.screencaptureui",
    "com.apple.dock",
    "com.apple.loginwindow",
    "com.apple.SecurityAgent",
    "com.apple.universalcontrol",
  ]

  /// 번들 ID가 비어 있는 프로세스용 이름 기반 제외 목록
  public static let excludedAppNames: Set<String> = [
    "Window Server", "Dock", "Control Center", "Spotlight",
    "Notification Center", "SystemUIServer", "loginwindow",
  ]

  public static func isExcluded(bundleID: String, appName: String) -> Bool {
    if excludedBundleIDs.contains(bundleID) { return true }
    return excludedAppNames.contains(appName)
  }

  /// 창 목록에 넣을지 — 크기·이름·제외 규칙을 한 곳에서 판단한다.
  public static func accepts(bundleID: String, appName: String,
                             title: String, width: CGFloat, height: CGFloat) -> Bool {
    if isExcluded(bundleID: bundleID, appName: appName) { return false }
    if width < minWidth || height < minHeight { return false }
    if appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    return true
  }
}

/// 창 1개를 읽은 결과(전송 전 스냅샷)
public struct WindowSnapshot: Equatable {
  public var target: WindowTarget
  /// 접근성으로 읽은 화면 텍스트(정리 후)
  public var text: String
  /// 사용자가 그 창에서 선택해 둔 텍스트(없으면 빈 문자열)
  public var selectedText: String
  /// 길어서 잘랐는지
  public var truncated: Bool
  /// 스크린샷을 함께 첨부했는지
  public var hasScreenshot: Bool
  public var capturedAt: Date

  public init(target: WindowTarget, text: String, selectedText: String = "",
              truncated: Bool = false, hasScreenshot: Bool = false,
              capturedAt: Date = Date()) {
    self.target = target
    self.text = text
    self.selectedText = selectedText
    self.truncated = truncated
    self.hasScreenshot = hasScreenshot
    self.capturedAt = capturedAt
  }

  /// 읽을 수 있는 텍스트가 하나도 없는가(스크린샷만 보내는 경우)
  public var hasNoText: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// 창 연결 첨부 문구 — 모델에게 주는 규칙과 파일 본문을 만든다.
///
/// Meta AI의 프롬프트와 같은 핵심을 지킨다:
///   ① 읽기 전용 ② 다시 읽을 수 없는 단일 스냅샷 ③ 조작을 약속하지 말 것.
public enum WindowContextPrompt {
  /// 접근성 트리에서 긁은 텍스트를 사람이 읽을 수 있게 정리한다.
  public static func sanitize(_ raw: String) -> String {
    var s = raw.replacingOccurrences(of: "\r\n", with: "\n")
               .replacingOccurrences(of: "\r", with: "\n")
    // 제어문자 제거(탭·줄바꿈은 유지)
    s = String(s.unicodeScalars.filter { scalar in
      if scalar == "\n" || scalar == "\t" { return true }
      return !CharacterSet.controlCharacters.contains(scalar)
    })
    // 줄 끝 공백 제거 + 3줄 이상 빈 줄을 2줄로
    var lines: [String] = []
    var blankRun = 0
    for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
      if trimmed.trimmingCharacters(in: .whitespaces).isEmpty {
        blankRun += 1
        if blankRun > 2 { continue }
        lines.append("")
      } else {
        blankRun = 0
        lines.append(trimmed)
      }
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 상한에서 자른다 — 가능하면 **줄 경계**에서 끊어 문장이 어색하게 잘리지 않게 한다.
  public static func truncate(_ text: String,
                              limit: Int = WindowContextLimits.maxTextCharacters)
    -> (text: String, truncated: Bool) {
    guard text.count > limit, limit > 0 else { return (text, false) }
    let cut = String(text.prefix(limit))
    if let lastNewline = cut.lastIndex(of: "\n"),
       cut.distance(from: cut.startIndex, to: lastNewline) > limit / 2 {
      return (String(cut[..<lastNewline]), true)
    }
    return (cut, true)
  }

  /// 첨부 텍스트 파일 이름 — 칩에 이 이름이 보인다.
  public static func textFileName(_ target: WindowTarget) -> String {
    "\(L("창 텍스트")) — \(safeComponent(target.appName)).txt"
  }

  /// 첨부 이미지 파일 이름
  public static func imageFileName(_ target: WindowTarget) -> String {
    "\(safeComponent(target.appName)) — \(L("창 스크린샷")).png"
  }

  /// 파일 이름에 쓸 수 없는 문자를 지운다 — 앱 이름에 `/`·`:`가 들어가도 하위 폴더로 새지 않게.
  public static func safeComponent(_ raw: String) -> String {
    let banned = CharacterSet(charactersIn: "/\\:*?\"<>|")
    let cleaned = String(raw.unicodeScalars.filter { !banned.contains($0) })
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Window" : cleaned
  }

  /// 모델이 읽는 본문. 첫 줄부터 "무엇인지"를 밝히고, 규칙을 먼저 둔다.
  public static func fileBody(_ snapshot: WindowSnapshot) -> String {
    let target = snapshot.target
    var out = """
    [\(L("창 연결"))] \(L("사용자가 이 창을 질문의 컨텍스트로 첨부했습니다."))
    - \(L("앱")): \(target.appName)
    - \(L("창 제목")): \(target.displayTitle)
    - \(L("읽은 시각")): \(Self.timestampFormatter.string(from: snapshot.capturedAt))

    \(L("규칙:"))
    - \(L("이 창은 읽기 전용 컨텍스트입니다. 클릭·입력·스크롤·메뉴 열기 등 어떤 조작도 할 수 없습니다."))
    - \(L("다시 읽을 수 없습니다. 이 스냅샷이 전부입니다."))
    - \(L("창 조작이 필요하면 사용자에게 무엇을 하면 되는지 알려주세요."))

    --- \(L("창 텍스트")) ---
    """
    if snapshot.hasNoText {
      out += "\n\(L("(읽을 수 있는 텍스트 없음 — 첨부한 스크린샷을 참고하세요)"))"
    } else {
      out += "\n\(snapshot.text)"
      if snapshot.truncated {
        out += "\n\(Lf("[안내: 길어서 앞 %d자만 담았습니다.]", WindowContextLimits.maxTextCharacters))"
      }
    }
    if !snapshot.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      out += "\n\n--- \(L("선택된 텍스트")) ---\n\(snapshot.selectedText)"
    }
    if snapshot.hasScreenshot {
      out += "\n\n\(L("이 창의 스크린샷이 이미지로 함께 첨부되어 있습니다."))"
    }
    return out
  }

  /// 시트 미리보기용 — 파일 본문에서 긴 머리말을 뺀 텍스트만.
  public static func previewText(_ snapshot: WindowSnapshot, limit: Int = 1_200) -> String {
    if snapshot.hasNoText { return L("읽을 수 있는 텍스트가 없습니다 — 스크린샷만 전송됩니다.") }
    let body = snapshot.text
    if body.count <= limit { return body }
    return String(body.prefix(limit)) + "\n…"
  }

  static let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: L10n.effective == .ko ? "ko_KR" : "en_US")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
  }()
}
