import SwiftUI
import AppKit

/// 대화 입력창 — Siri 입력창처럼 상자 안에서 1~`maxLines`줄까지 늘어나고, 넘치면 안에서 스크롤된다.
/// - **Enter = 전송 / Shift+Enter = 줄바꿈**
/// - AppKit `NSTextView`를 직접 쓰는 이유:
///   1) 한글 IME 조합 확정과 전송 시점이 어긋나 전송한 글이 입력창에 남던 문제 제거(전송 시 `string`을 직접 읽고 비운다)
///   2) 이 환경에서는 `NSScrollView`·부모 뷰가 자식 뷰를 클리핑하지 않아(텍스트가 상자 밖으로 샘) 스크롤뷰를 쓰지 않는다
///      → 텍스트 뷰 크기를 **상자 크기와 같게** 두고(스스로 클리핑) 안쪽 여백을 밀어 스크롤을 구현한다
struct ChatInputField: NSViewRepresentable {
  @Binding var text: String
  /// 측정된 입력 영역 높이(pt) — 호출한 쪽이 `.frame(height:)` 로 고정한다
  @Binding var height: CGFloat
  /// 응답 대기 중이면 Enter로 전송하지 않는다(전송 버튼과 같은 규칙)
  var isBusy: Bool
  /// 최대 줄 수 — 넘으면 입력창 안에서 스크롤
  var maxLines: Int = 5
  /// 값이 바뀌면 입력창에 포커스를 준다(질문 수정·다시 응답에서 사용)
  var focusToken: UUID?
  /// 폰트 — pill 은 더 큰 폰트를 넘긴다(줄 높이도 이 값으로 계산한다)
  var font: NSFont = ChatInputField.defaultFont
  /// ⌘Return — 지정하면 Enter 대신 이 동작을 맡는다(pill: 대화 창 열기)
  var onCommandReturn: (() -> Void)?
  /// Esc — 지정하면 취소 동작을 맡는다(pill: 닫기)
  var onCancel: (() -> Void)?
  /// 전송 요청 — 확정된 현재 문자열을 함께 넘긴다(IME 조합 확정분 포함)
  var onSubmit: (String) -> Void

  /// 글자 상자 위/아래 여백(1줄일 때 마이크 버튼 높이에 맞춘다)
  static let verticalPadding: CGFloat = 6
  static let horizontalPadding: CGFloat = 3
  /// 대화 입력창 기본 폰트
  static let defaultFont = NSFont.systemFont(ofSize: 13)

  /// 폰트별 한 줄 높이(캐시) — 크기만으로 구분한다
  private static var lineHeightCache: [CGFloat: CGFloat] = [:]

  /// AppKit이 실제로 쓰는 줄 높이(폰트 기준) — 상자 높이와 스크롤 오프셋을 이 값의 배수로 맞춘다
  static func lineHeight(for font: NSFont) -> CGFloat {
    let key = font.pointSize
    if let cached = lineHeightCache[key] { return cached }
    let storage = NSTextStorage(string: "가나다", attributes: [.font: font])
    let lm = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(lm)
    lm.addTextContainer(container)
    lm.ensureLayout(for: container)
    let h = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    let value = h > 1 ? h : 16
    lineHeightCache[key] = value
    return value
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> ChatTextView {
    let tv = ChatTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
    tv.delegate = context.coordinator
    tv.drawsBackground = false
    tv.isRichText = false
    tv.font = font
    tv.textColor = .labelColor
    tv.insertionPointColor = .labelColor
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.isAutomaticTextReplacementEnabled = false
    tv.isAutomaticSpellingCorrectionEnabled = false
    tv.isContinuousSpellCheckingEnabled = false
    tv.allowsUndo = true
    // 크기는 SwiftUI가 정한다(스크롤뷰 없이 자체 클리핑)
    tv.isVerticallyResizable = false
    tv.isHorizontallyResizable = false
    tv.autoresizingMask = [.width, .height]
    tv.minSize = .zero
    tv.clipsToBounds = true      // 스크롤로 밀린 글자가 상자 밖(위/아래)으로 새지 않게 — 이 환경은 기본 클리핑이 없다
    tv.textContainerInset = NSSize(width: Self.horizontalPadding, height: Self.verticalPadding)
    tv.textContainer?.widthTracksTextView = true
    tv.textContainer?.heightTracksTextView = true      // 레이아웃을 상자 높이 안으로 제한
    tv.textContainer?.lineFragmentPadding = 2
    tv.string = text
    tv.onScroll = { [weak coordinator = context.coordinator] dy in coordinator?.scroll(by: dy) }
    // 폭이 확정된 뒤에 한 번 더 측정한다(초기 폭 0 상태에서 재는 것을 막는다)
    tv.onWidthSettled = { [weak coordinator = context.coordinator, weak tv] in
      guard let tv else { return }
      coordinator?.layoutPass(width: tv.bounds.width)
    }
    context.coordinator.textView = tv
    return tv
  }

  func updateNSView(_ tv: ChatTextView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.textView = tv
    if tv.string != text, !tv.hasMarkedText() {
      tv.string = text
      tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
      // 값을 직접 넣은 경우엔 textDidChange 가 오지 않는다 → 여기서 다시 잰다.
      // (pill 처럼 "나중에 채워 넣는" 입력창의 높이가 1줄로 남던 문제)
      context.coordinator.layoutPass(width: tv.bounds.width)
    }
    context.coordinator.layoutPass(width: tv.bounds.width)
    let coordinator = context.coordinator
    DispatchQueue.main.async { [weak tv] in
      // 첫 레이아웃 때는 아직 폭이 0일 수 있다 — 폭이 잡힌 뒤 한 번 더 측정한다.
      guard let tv else { return }
      coordinator.layoutPass(width: tv.bounds.width)
    }
    if let token = focusToken,
       context.coordinator.lastFocusToken != token {
      context.coordinator.lastFocusToken = token
      DispatchQueue.main.async { [weak tv] in
        guard let tv, let window = tv.window else { return }
        window.makeFirstResponder(tv)
      }
    }
  }

  // MARK: - 측정 (뷰 상태에 의존하지 않는다)

  /// 이 입력창이 쓰는 한 줄 높이
  var oneLineHeight: CGFloat { ChatInputField.lineHeight(for: font) }

  // MARK: - 스크롤 휠을 받는 텍스트 뷰

  final class ChatTextView: NSTextView {
    var onScroll: ((CGFloat) -> Void)?
    /// **폭이 정해지면** 알려준다 — 측정은 폭이 잡힌 뒤에야 정확하다
    /// (SwiftUI 는 update 시점의 view 폭이 0일 수 있다 — pill 입력창이 여기에 걸렸었다)
    var onWidthSettled: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layout() {
      super.layout()
      if abs(bounds.width - lastWidth) > 0.5 {
        lastWidth = bounds.width
        onWidthSettled?()
      }
    }

    override func scrollWheel(with event: NSEvent) {
      onScroll?(event.scrollingDeltaY)
    }
  }

  // MARK: - Coordinator

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ChatInputField
    weak var textView: ChatTextView?
    private var reported: CGFloat = 0
    /// 화면에 가장 위에 보이는 줄 인덱스(스크롤 위치)
    private var firstLine = 0
    /// 마지막으로 처리한 포커스 요청 — 같은 토큰으로 반복 포커스를 주지 않는다.
    var lastFocusToken: UUID?

    init(_ parent: ChatInputField) {
      self.parent = parent
      self.reported = parent.height
    }

    func textDidChange(_ notification: Notification) {
      guard let tv = notification.object as? NSTextView else { return }
      if parent.text != tv.string { parent.text = tv.string }
      layoutPass(width: tv.bounds.width)
      // Shift+Enter 직후에는 레이아웃이 한 프레임 늦게 확정될 수 있다 — 한 번 더 맞춘다.
      DispatchQueue.main.async { [weak self, weak tv] in
        guard let self, let tv else { return }
        self.layoutPass(width: tv.bounds.width)
      }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let tv = textView else { return }
      layoutPass(width: tv.bounds.width)
      DispatchQueue.main.async { [weak self, weak tv] in
        guard let self, let tv else { return }
        self.layoutPass(width: tv.bounds.width)
      }
    }

    /// 높이와 스크롤 위치를 AppKit 레이아웃 기준으로 계산해 반영한다
    func layoutPass(width: CGFloat, caretFollows: Bool = true) {
      guard let tv = textView else { return }
      let w = width > 4 ? width : tv.bounds.width
      guard w > 4 else { return }
      let info = measure(tv)
      guard let info else { return }   // 글자가 없으면 측정할 것이 없다(빈 입력창)
      let total = max(1, info.tops.count)
      let visible = min(total, parent.maxLines)

      // 캐럿이 있는 줄이 보이도록 첫 줄을 맞춘다(직접 스크롤한 경우엔 유지)
      var first = min(firstLine, max(0, total - visible))
      if caretFollows {
        let caret = min(max(0, info.caretLine), total - 1)
        if caret >= first + visible { first = min(caret - visible + 1, max(0, total - visible)) }
        if caret < first { first = caret }
      }
      firstLine = first

      let tops = info.tops
      let bots = info.bots
      let topY = first < tops.count ? tops[first] : 0
      // 높이는 **화면에 보이는 줄 경계까지**로 딱 맞춘다(T-27).
      // 전체 높이(usedRect)를 쓰면 줄 경계와 어긋나 맨 위 줄이 반쯤 잘려 보인다.
      let lastVisible = min(first + visible - 1, max(0, total - 1))
      let lineHeight = parent.oneLineHeight
      let bottomY = lastVisible < bots.count
        ? bots[lastVisible]
        : topY + lineHeight * CGFloat(visible)
      let area = max(lineHeight, bottomY - topY)
      let inset = ChatInputField.verticalPadding - topY
      if abs(tv.textContainerInset.height - inset) > 0.01 {
        tv.textContainerInset = NSSize(width: ChatInputField.horizontalPadding, height: inset)
        tv.needsDisplay = true
      }
      let newHeight = area + ChatInputField.verticalPadding * 2
      guard abs(newHeight - reported) > 0.5 else { return }
      reported = newHeight
      let value = newHeight
      DispatchQueue.main.async { [weak self] in
        guard let self, abs(self.parent.height - value) > 0.5 else { return }
        self.parent.height = value
      }
    }

    // MARK: - AppKit 레이아웃에서 줄 정보 읽기

    private struct LineInfo {
      var usedHeight: CGFloat      // 전체 글자 높이(컨테이너 기준)
      var tops: [CGFloat]          // 각 줄의 위쪽 y
      var bots: [CGFloat]          // 각 줄의 아래쪽 y(다음 줄 위와 같다)
      var caretLine: Int           // 캐럿이 있는 줄 인덱스
    }

    /// 측정 동안만 컨테이너 높이 제한을 풀고 레이아웃을 읽는다(AppKit과 같은 줄 경계를 얻기 위해)
    private func measure(_ tv: NSTextView) -> LineInfo? {
      // AppKit 레이아웃은 메인 스레드 전용이다. 다른 스레드에서 컨테이너 크기를 건드리면
      // 창 드래그 영역 무효화 예외로 앱이 죽는다(2026-10-21 크래시) — 그 경우 측정만 건너뛴다.
      guard Thread.isMainThread else { return nil }
      guard let lm = tv.layoutManager, let c = tv.textContainer else { return nil }
      let savedTracks = c.heightTracksTextView
      let savedSize = c.containerSize
      c.heightTracksTextView = false
      c.containerSize = NSSize(width: savedSize.width, height: CGFloat.greatestFiniteMagnitude)
      lm.ensureLayout(for: c)
      defer {
        c.containerSize = savedSize
        c.heightTracksTextView = savedTracks
      }
      let glyphs = lm.numberOfGlyphs
      guard glyphs > 0 else { return nil }
      var tops: [CGFloat] = []
      var bots: [CGFloat] = []
      var idx = glyphs
      while idx > 0 {
        var range = NSRange(location: 0, length: 0)
        let rect = lm.lineFragmentRect(forGlyphAt: idx - 1, effectiveRange: &range)
        tops.append(rect.minY)
        bots.append(rect.maxY)
        if range.location == 0 || range.length == 0 { break }
        idx = range.location
      }
      tops.reverse()
      bots.reverse()

      let ns = tv.string as NSString
      // 문자열이 **줄바꿈으로 끝나면** 마지막 빈 줄은 글리프가 없어 위 루프에 안 잡힌다.
      // 그 줄을 빼면 Shift+Enter로 새 줄을 만들었을 때 높이가 자라지 않고 커서가 가려진다.
      let endsWithNewline = ns.length > 0 && ns.hasSuffix("\n")
      if endsWithNewline {
        let extra = lm.extraLineFragmentRect
        if extra.height > 1 {
          tops.append(extra.minY)
          bots.append(extra.maxY)
        }
      }

      let caretChar = max(0, min(tv.selectedRange().location, ns.length))
      let caretAtEnd = caretChar >= ns.length
      let caretLine: Int
      if endsWithNewline && caretAtEnd && !tops.isEmpty {
        caretLine = tops.count - 1
      } else {
        let caretGlyph = caretChar > 0 && ns.length > 0
          ? lm.glyphIndexForCharacter(at: min(caretChar - 1, ns.length - 1))
          : 0
        let caretTop = lm.lineFragmentRect(forGlyphAt: min(caretGlyph, glyphs - 1),
                                           effectiveRange: nil).minY
        caretLine = tops.lastIndex(where: { $0 <= caretTop + 0.5 }) ?? 0
      }
      return LineInfo(usedHeight: lm.usedRect(for: c).maxY, tops: tops, bots: bots,
                      caretLine: caretLine)
    }

    /// 스크롤 휠 — 한 줄 단위로 위/아래 이동
    func scroll(by delta: CGFloat) {
      guard let tv = textView, abs(delta) > 0.5 else { return }
      let step = delta > 0 ? -1 : 1
      firstLine = max(0, firstLine + step)
      layoutPass(width: tv.bounds.width, caretFollows: false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      // Esc — 지정된 취소 동작이 있으면 그쪽으로 넘긴다(pill: 닫기)
      if commandSelector == #selector(NSResponder.cancelOperation(_:)),
         let onCancel = parent.onCancel {
        onCancel()
        return true
      }
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
      let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
      if shift {
        textView.insertNewlineIgnoringFieldEditor(nil)      // Shift+Enter = 줄바꿈
        return true
      }
      // ⌘Return — 지정된 동작이 있으면 전송 대신 그걸 한다(pill: 대화 창 열기)
      if let onCommandReturn = parent.onCommandReturn,
         NSApp.currentEvent?.modifierFlags.contains(.command) == true {
        onCommandReturn()
        return true
      }
      // 한글 등 조합 중이면 먼저 확정한다(첫 Enter에도 바로 전송되게)
      if textView.hasMarkedText() {
        let marked = (textView.string as NSString).substring(with: textView.markedRange())
        NSLog("[QuickTalk] 조합 중 Enter — 조합 확정 후 전송")
        textView.insertText(marked, replacementRange: textView.markedRange())
      }
      let value = textView.string
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
      guard !parent.isBusy else { return true }             // 응답 대기 중에는 전송하지 않음
      firstLine = 0
      parent.onSubmit(value)
      return true
    }
  }
}
