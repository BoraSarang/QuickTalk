import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

// [INFO] [FEATURE] 대화 입력독 (Xcode 단일 타깃: Core 파일 동시 컴파일)

/// 아직 전송하지 않은 첨부 1건 — 미리보기(썸네일)와 전송을 위해 실제 파일 위치를 함께 들고 있다.
/// 보관함 검색 결과를 열 때 어느 턴으로 갈지 — ContentView가 스크롤·깜빡임에 쓴다.
/// `token` 덕분에 같은 턴을 다시 눌러도 새 요청으로 인식된다.
struct SearchFocusRequest: Equatable {
  let conversationID: UUID
  let turnID: UUID
  let query: String
  let token = UUID()
}

struct PendingAttachment: Identifiable, Equatable {
  let id = UUID()
  var name: String
  var url: URL?
  var kind: Attachment.Kind

  /// 첨부 칩·미리보기에 쓸 이미지(있으면)
  var image: NSImage? {
    guard kind == .image, let url else { return nil }
    return NSImage(contentsOf: url)
  }

  /// 파일 크기 문구(있으면)
  var sizeText: String? {
    guard let url,
          let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }
}

final class UIStore: ObservableObject {
  @Published var conversation = Conversation()
  @Published var settings = QuickTalkSettings() {
    didSet { saveSettings() }
  }
  @Published var draft = ""
  @Published var attached: [PendingAttachment] = []
  @Published var voiceRecording = false
  /// 응답 대기 상태 — 입력독에 "응답 중" 표시를 띄우고 중복 전송을 막는다
  @Published var isReplying = false
  // MARK: - 웹 검색 (PLAN_v0.14)
  /// 검색 결과를 기다리는 중 — 응답 말풍선 대신 "웹에서 찾는 중…"을 보여 준다
  @Published var isSearching = false
  /// 입력독 🌐 — **이번 질문만** 검색을 강제한다(전송 후 자동 해제)
  @Published var forceWebSearch = false
  /// 설정 › AI의 [검색 테스트] 결과(건수·지연 또는 오류 코드)
  @Published var webSearchTestResult = ""
  @Published var webSearchTesting = false
  /// 설정 › AI의 [답변 API 테스트] 결과
  @Published var answerTestResult = ""
  @Published var answerTesting = false
  /// 공통 메모리 — 모든 대화에 적용되는 사용자 작성 사실(PLAN_v0.16).
  @Published var memoryEntries: [GlobalMemoryEntry] = [] {
    didSet { saveMemory() }
  }
  /// 메모리 저장·가져오기 안내(실패 포함).
  @Published var memoryNotice: String?
  private var suppressMemorySave = false
  private let searchCache = SearchCache()
  private let answerCache = ExaAnswerCache()
  /// 검색 필요 판정 캐시 — 같은 질문·직전 맥락이면 10분간 모델을 다시 부르지 않는다.
  private var searchDecisionCache: [String: (needed: Bool, at: Date)] = [:]
  private let searchDecisionTTL: TimeInterval = 600
  // MARK: - 대화 기억 정리 (T-71)
  /// 요약을 만들고 있는 중 — 입력독 위 배너에 표시한다(응답 대기와 별개).
  @Published var isCompacting = false
  /// 정리 중인 대화방 — 다른 방으로 전환했을 때 배너가 섞이지 않게 한다.
  @Published var compactingConversationID: UUID?
  /// 정리 실패·안내 문구(자동 정리 중에는 조용히, 수동은 사유 표시).
  @Published var compactMessage: String?
  /// 지금 토큰을 받고 있는 어시스턴트 턴 — 첫 글자가 오면 점 표시를 숨기고 자동 스크롤한다
  @Published var streamingTurnID: UUID?
  /// QA 렌더에서 설정을 바꿀 때 저장을 막는다
  private var suppressSettingsSave = false
  private var replyStartedAt: Date?
  /// 진행 중인 응답 Task — 로컬 모델은 첫 토큰까지 수 분 걸릴 수 있어 **사용자가 중지**할 수 있다.
  private var replyTask: Task<Void, Never>?
  /// 질문 수정/다시 응답으로 입력창을 채웠을 때 포커스를 되돌리기 위한 토큰
  @Published var composerFocusToken: UUID?

  /// 응답 대기 경과(초)
  var replySeconds: Int { Int(Date().timeIntervalSince(replyStartedAt ?? Date())) }

  /// 응답 중 표시에 쓸 프로바이더·모델 라벨
  var replySourceLabel: String {
    guard let p = settings.activeProvider else { return L("AI 미설정") }
    let model = p.model.isEmpty ? p.type.displayName : p.model
    return "\(p.displayName) · \(model)"
  }
  let speech = AppleSpeechService()
  /// Edge TTS(온라인) — `edge-tts` CLI로 합성한 mp3를 재생한다
  let edgeSpeech = EdgeSpeechService()
  /// Piper TTS(로컬) — `piper` CLI로 합성한 wav를 재생한다
  let piperSpeech = PiperSpeechService()
  /// 최근 클립보드 스트립 (PLAN_v0.12) — 만료 2분 · 최대 5개
  let clipboard = ClipboardService()
  // MARK: - QuickShelf 상태 (PLAN_v0.13)
  @Published var shelfTab: ShelfTab = .clipboard
  @Published var shelfFiles: [ShelfFile] = []
  @Published var shelfCaptures: [ShelfCapture] = []
  /// 호버 미리보기 대상(패널 왼쪽 별도 창)
  @Published var shelfPreview: ShelfPreviewTarget?
  /// 권한·실패 안내 문구(패널 상단에 표시)
  @Published var shelfNotice: String?
  /// 읽어주기(TTS) 재생 중 — 헤더·메시지 버튼이 **중지**로 바뀐다
  @Published var isSpeaking = false
  /// 음성 설정 묶음 — 바뀐 항목이 있을 때만 서비스에 다시 넘긴다(튜플 8개는 Equatable이 없다)
  private struct SpeechSettingsKey: Equatable {
    let locale: String
    let voice: String
    let ttsLanguage: String
    let rate: Double
    let edgeVoice: String
    let edgeBinary: String
    let piperModel: String
    let piperBinary: String
  }

  /// 지금 읽고 있는 응답(턴) — 그 말풍선만 중지 버튼이 된다
  @Published var speakingTurnID: UUID?
  /// 전역 단축키 등록 결과(동작별) — 설정 창의 ⚠️ 표시
  @Published var shortcutStatus: [ShortcutAction: Bool] = [:]
  /// 안내를 눌렀을 때 할 일(권한 요청 등) — 없으면 그냥 안내
  @Published var shelfNoticeAction: ShelfNoticeAction?
  /// 안내 배너의 동작 — 배너 본문을 누르면 실행한다
  enum ShelfNoticeAction: Equatable {
    case screenRecording
  }

  /// 안내를 띄우고(선택) 눌렀을 때 할 일을 함께 지정한다.
  /// `nil`로 지우면 동작도 같이 지운다(이전 안내의 동작이 남지 않게).
  func showShelfNotice(_ text: String?, action: ShelfNoticeAction? = nil) {
    shelfNotice = text
    shelfNoticeAction = text == nil ? nil : action
  }

  /// 첨부 안내(지원하지 않는 형식 등) — 입력독 위 배너로 표시한다(무음 실패 금지)
  @Published var attachNotice: String?
  /// 보관함 검색 결과에서 이동·강조할 턴(ContentView가 소비한 뒤 nil로 지운다)
  @Published var searchFocus: SearchFocusRequest?
  private var attachNoticeToken = UUID()
  /// 대화창 안에 도킹된 상태(창 오른쪽에 3탭 허브가 붙는다) — 창이 열려 있을 때의 기본 위치
  @Published var shelfDocked = false
  private var whisperRecorder: AVAudioRecorder?
  private var bag = Set<AnyCancellable>()
  private let core = ConversationStore()
  private let settingsKey = "QuickTalk.settings"

  init() {
    if let data = UserDefaults.standard.data(forKey: settingsKey),
       let loaded = try? JSONDecoder().decode(QuickTalkSettings.self, from: data) {
      // 구버전 기본값(Ctrl+Space) 마이그레이션: 미변경 유저는 Cmd+Space로 승격
      var s = loaded
      var changed = false
      if s.globalShortcut == "Ctrl+Space" { s.globalShortcut = "Cmd+Space"; changed = true }
      // QuickShelf 기본 단축키 ⌥⌘V가 다른 앱의 '경로 복사'와 겹쳐 ⇧⌥V로 옮긴다.
      // 저장값이 옛 기본값이면 매번 승격한다(실행 중이던 앱이 옛 값을 다시 저장해도 다음 실행에서 바로잡힘).
      if s.shelfShortcut == "Option+Cmd+V" {
        s.shelfShortcut = "Option+Shift+V"
        changed = true
      }
      // 활성 프로바이더가 원격인데 키체인에 키가 없으면 Apple FM으로 폴백 (키 없는 실패 방지)
      if let active = s.activeProvider {
        let needsKey = active.type == .openAICompatible
        let keyMissing = active.secretID.isEmpty || !SecretStore.has(account: active.secretID)
        if needsKey && keyMissing, let fallback = Self.keylessFallbackID(in: s), fallback != active.id {
          s.activeProviderID = fallback
          changed = true
        }
      } else {
        s.activeProviderID = LLMProviderConfig.appleFMID
        changed = true
      }
      // 표시 정책: 메뉴바·Dock 둘 다 숨김 상태는 진입점이 없으므로 Dock을 켠다
      if s.normalizeVisibility() { changed = true }
      settings = s
      if changed { saveSettings() }
    }
    speech.$isRecording.assign(to: &$voiceRecording)
    // 동기 구독 — 중지 직후 새로 읽기 시작할 때 "false" 이벤트가 뒤늦게 도착해
    // 새로 지정한 speakingTurnID를 지워 버리지 않게 한다.
    // 세 엔진(Apple·Edge·Piper) 중 하나라도 재생 중이면 '읽는 중'이다
    speech.$isSpeaking
      .combineLatest(edgeSpeech.$isSpeaking, piperSpeech.$isSpeaking)
      .map { $0 || $1 || $2 }
      .removeDuplicates()
      .sink { [weak self] speaking in
        guard let self else { return }
        self.isSpeaking = speaking
        guard !speaking else { return }
        // 중지 직후 다른 엔진으로 새로 읽기 시작할 수 있다 — 잠깐 뒤에도 조용할 때만 턴 표시를 지운다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
          guard let self, !self.isSpeaking else { return }
          self.speakingTurnID = nil
        }
      }
      .store(in: &bag)
    speech.onPartial = { [weak self] t in self?.draft = t }
    speech.onFinal = { [weak self] t in self?.draft = t }
    // 음성 설정(받아쓰기 언어·읽어주기 목소리/속도)을 서비스에 반영하고, 바뀔 때마다 다시 넘긴다
    applySpeechSettings()
    $settings
      .dropFirst()
      .map { s in
        SpeechSettingsKey(locale: s.appleSpeechLocale,
                          voice: s.ttsVoiceID,
                          ttsLanguage: s.ttsLanguage,
                          rate: s.ttsRate,
                          edgeVoice: s.edgeVoice,
                          edgeBinary: s.edgeBinaryPath,
                          piperModel: s.piperModelPath,
                          piperBinary: s.piperBinaryPath)
      }
      .removeDuplicates()
      .sink { [weak self] v in
        self?.speech.configure(locale: v.locale, voice: v.voice, ttsLanguage: v.ttsLanguage, rate: v.rate)
        self?.edgeSpeech.configure(voice: v.edgeVoice, rate: v.rate, binary: v.edgeBinary)
        self?.piperSpeech.configure(rate: v.rate, model: v.piperModel, binary: v.piperBinary)
      }
      .store(in: &bag)
    // 중첩 ObservableObject(ClipboardService)의 변경을 UIStore 변경으로 전달한다.
    // (뷰가 UIStore만 관찰하면 항목 소멸이 스트립 표시 조건에 반영되지 않는다)
    clipboard.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    // Edge·Piper TTS의 '최근 오류' 표시도 설정 창에서 바로 갱신되게
    edgeSpeech.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    piperSpeech.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    clipboard.start()
    memoryEntries = GlobalMemoryFile.load()
    loadArchive()
    restoreLastConversation()
  }

  // MARK: - 클립보드 스트립 → 입력/첨부 (PLAN_v0.12)

  /// 텍스트/링크: 입력창에 이어 붙인다(커서 위치 개념은 입력창 끝으로 단순화)
  func insertClipboardText(_ item: ClipboardItem) {
    let text = clipboard.displayText(item)
    guard !text.isEmpty else { return }
    if draft.isEmpty { draft = text }
    else if draft.hasSuffix(" ") || draft.hasSuffix("\n") { draft += text }
    else { draft += " " + text }
    NSLog("[QuickTalk] 클립보드 텍스트 입력창 삽입 kind=%@ 길이=%d", item.kind.rawValue, text.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// 창 안 허브에서 항목을 고른 뒤에는 허브를 접는다 — 오버레이가 입력독·전송 버튼을 가리지 않게
  /// (목업 v0.6의 드로어 동작. 여러 개를 붙이려면 ⌥⌘V로 다시 열면 된다 — 카드·탭 상태는 그대로 남는다)
  private func closeShelfAfterPick() {
    guard shelfDocked else { return }
    withAnimation(.easeInOut(duration: 0.18)) { shelfDocked = false }
  }

  /// 스트립 항목 누름 — 민감 항목은 **먼저 공개**하고, 다시 누르면 삽입/첨부 후 스트립에서 사라진다.
  func tapClipboard(_ item: ClipboardItem) {
    if item.isSensitive && !clipboard.isRevealed(item.id) {
      clipboard.reveal(item.id)
      NSLog("[QuickTalk] 클립보드 민감 항목 공개 (kind=%@)", item.kind.rawValue)
      return
    }
    attachClipboard(item)
    // 사용한 항목은 스트립에서 제거한다(같은 것을 계속 붙는 문제 방지)
    clipboard.remove(item.id)
  }

  /// 이미지: 입력창에 넣을 수 없으므로 임시 파일로 저장 후 첨부로 추가
  func attachClipboard(_ item: ClipboardItem) {
    switch item.kind {
    case .image:
      guard let data = item.imageData, let url = Self.writeTempImage(data) else {
        NSLog("[ERROR] E-MAC-RENDER-0001 클립보드 이미지 저장 실패")
        return
      }
      attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: .image))
      NSLog("[QuickTalk] 클립보드 이미지 첨부 추가 (개수=%d)", attached.count)
      closeShelfAfterPick()
      NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
    case .file:
      let name = item.text
      guard Attachment.isSupported(filename: name) else {
        setAttachNotice(Self.unsupportedMessage([name]))
        return
      }
      if !attached.contains(where: { $0.name == name }) {
        // 클립보드가 준 파일 경로를 그대로 넘긴다 — 없으면 전송 시 이름만 알린다(P1)
        attached.append(PendingAttachment(name: name, url: item.fileURL, kind: .file))
        if item.fileURL == nil {
          setAttachNotice(Lf("「%@」의 파일 위치를 얻지 못해 이름만 전달됩니다", name))
        } else if let url = item.fileURL, !FileManager.default.fileExists(atPath: url.path) {
          setAttachNotice(Lf("「%@」 파일이 이미 사라졌습니다 — 본문 없이 이름만 전달됩니다", name))
        }
      }
      NSLog("[QuickTalk] 클립보드 파일 첨부 추가 (개수=%d)", attached.count)
      closeShelfAfterPick()
    case .text, .link:
      insertClipboardText(item)
    }
  }

  static func isImageName(_ name: String) -> Bool { Attachment.isImageName(name) }

  // MARK: - 첨부 안내(무음 실패 금지)

  /// 지원하지 않는 형식 등을 입력독 위 배너로 알린다([HARD] 무음 실패 금지). 9초 뒤 스스로 사라진다.
  func setAttachNotice(_ text: String) {
    attachNotice = text
    let token = UUID()
    attachNoticeToken = token
    DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
      guard let self, self.attachNoticeToken == token else { return }
      self.attachNotice = nil
    }
  }

  /// 걸러낸 파일 안내 문구 — 이름은 앞 3개만 보여준다(로그에는 개수만)
  static func unsupportedMessage(_ names: [String]) -> String {
    guard !names.isEmpty else { return "" }
    let list = names.prefix(3).joined(separator: ", ")
    let extra = names.count > 3 ? Lf(" 외 %d건", names.count - 3) : ""
    NSLog("[WARN] E-MAC-MODEL-0001 지원하지 않는 첨부 %d건 제외", names.count)
    return Lf("첨부할 수 없는 형식입니다: %@%@ — 텍스트·코드 파일·PDF·이미지만 첨부됩니다", list, extra)
  }

  // MARK: - QuickShelf: 파일 · 캡처 (PLAN_v0.13)

  /// QuickShelf 파일·캡처 보관 폴더
  static var shelfDir: URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let dir = base.appendingPathComponent("QuickTalk/shelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// 파일 선택 결과를 파일 탭에 추가한다(중복 경로는 무시).
  @discardableResult
  func addShelfFiles(_ urls: [URL]) -> Int {
    var added = 0
    var rejected: [String] = []
    for url in urls {
      guard Attachment.isSupported(filename: url.lastPathComponent) else {
        rejected.append(url.lastPathComponent)     // 조용히 버리지 않는다(P3)
        continue
      }
      if shelfFiles.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { continue }
      let kind: Attachment.Kind = Self.isImageName(url.lastPathComponent) ? .image : .file
      shelfFiles.insert(ShelfFile(name: url.lastPathComponent, url: url, kind: kind), at: 0)
      added += 1
    }
    if !rejected.isEmpty { showShelfNotice(Self.unsupportedMessage(rejected)) }
    if added > 0 {
      NSLog("[QuickShelf] 파일 %d건 추가 (총 %d)", added, shelfFiles.count)
      shelfTab = .files
    }
    return added
  }

  func removeShelfFile(_ id: UUID) {
    shelfFiles.removeAll { $0.id == id }
  }

  /// 파일 카드 클릭 → 대화 첨부. 사용한 카드는 목록에서 사라진다(원본 파일은 그대로).
  func attachShelfFile(_ file: ShelfFile) {
    if attached.contains(where: { $0.name == file.name }) {
      showShelfNotice(Lf("이미 첨부된 파일입니다: %@", file.name))
      return
    }
    attached.append(PendingAttachment(name: file.name, url: file.url, kind: file.kind))
    removeShelfFile(file.id)
    NSLog("[QuickShelf] 파일 첨부 (이름=%@, 첨부=%d)", file.name, attached.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// 캡처 결과를 저장하고 캡처 탭 맨 위에 넣는다.
  @discardableResult
  func addCapture(png: Data, pixelWidth: Int, pixelHeight: Int, source: ShelfCapture.Source) -> ShelfCapture? {
    guard let dir = Self.shelfDir else { return nil }
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let base = "캡처-\(source.label.replacingOccurrences(of: " ", with: ""))-\(df.string(from: Date()))"
    var url = dir.appendingPathComponent(base + ".png")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base)-\(n).png")
      n += 1
    }
    do { try png.write(to: url) } catch {
      NSLog("[ERROR] E-MAC-RENDER-0001 캡처 저장 실패")
      return nil
    }
    let capture = ShelfCapture(url: url,
                               thumbnail: Self.thumbnailPNG(png, maxSide: 480),
                               width: pixelWidth, height: pixelHeight, source: source)
    shelfCaptures.insert(capture, at: 0)
    shelfTab = .capture
    NSLog("[QuickShelf] 캡처 추가 source=%@ %dx%d (총 %d)",
          source.rawValue, pixelWidth, pixelHeight, shelfCaptures.count)
    return capture
  }

  func removeCapture(_ id: UUID) {
    if let c = shelfCaptures.first(where: { $0.id == id }) {
      try? FileManager.default.removeItem(at: c.url)
    }
    shelfCaptures.removeAll { $0.id == id }
  }

  func clearCaptures() {
    for c in shelfCaptures { try? FileManager.default.removeItem(at: c.url) }
    shelfCaptures.removeAll()
  }

  /// 캡처 카드 툴바 — 클립보드 복사(다른 앱에 바로 붙여넣기)
  func copyCapture(_ capture: ShelfCapture) {
    guard let image = NSImage(contentsOf: capture.url) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([image])
    showShelfNotice(L("캡처를 클립보드에 복사했습니다."))
    NSLog("[QuickShelf] 캡처 클립보드 복사")
  }

  /// 캡처 카드 툴바 — 다른 이름/위치로 저장
  func saveCaptureAs(_ capture: ShelfCapture) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = capture.url.lastPathComponent
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      try FileManager.default.copyItem(at: capture.url, to: url)
      showShelfNotice(L("캡처를 저장했습니다."))
      NSLog("[QuickShelf] 캡처 저장")
    } catch {
      showShelfNotice(L("캡처 저장에 실패했습니다."))
      NSLog("[ERROR] E-MAC-RENDER-0001 캡처 저장 실패")
    }
  }

  /// 캡처 카드 클릭 → 대화 첨부. 첨부용 임시 복사본을 만든 뒤 카드와 원본을 지운다.
  /// (첨부가 원본 경로를 가리킨 채 파일이 사라지는 문제를 막는다)
  func attachCapture(_ capture: ShelfCapture) {
    guard let data = try? Data(contentsOf: capture.url) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    let base = capture.url.deletingPathExtension().lastPathComponent
    guard let url = Self.writeTempImage(data, name: base) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: .image))
    removeCapture(capture.id)
    NSLog("[QuickShelf] 캡처 첨부 (첨부=%d)", attached.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// PNG → 축소 PNG(카드 썸네일)
  static func thumbnailPNG(_ data: Data, maxSide: CGFloat) -> Data? {
    guard let image = NSImage(data: data) else { return data }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return data }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = NSSize(width: max(1, (size.width * scale).rounded()),
                        height: max(1, (size.height * scale).rounded()))
    let thumb = NSImage(size: target)
    thumb.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: target),
               from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    thumb.unlockFocus()
    guard let tiff = thumb.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return data }
    return rep.representation(using: .png, properties: [:])
  }

  func removeAttachment(_ id: UUID) { attached.removeAll { $0.id == id } }

  /// 앱 지원 폴더에 임시 이미지 파일을 만든다 — 첨부 칩에 사람이 알아볼 이름이 보이도록
  /// 크기·시각을 파일명에 넣는다(예: 붙여넣은 이미지 600x300-215412.png)
  private static func writeTempImage(_ data: Data, name: String? = nil) -> URL? {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("QuickTalk/clip", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let size = NSBitmapImageRep(data: data).map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "image"
    let df = DateFormatter()
    df.dateFormat = "HHmmss"
    let stem: String
    if let name, !name.isEmpty {
      stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    } else {
      stem = "붙여넣은 이미지 \(size)-\(df.string(from: Date()))"
    }
    var url = dir.appendingPathComponent("\(stem).png")
    var n = 2
    while fm.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(stem)-\(n).png")
      n += 1
    }
    do { try data.write(to: url); return url } catch { return nil }
  }

  private func saveSettings() {
    guard !suppressSettingsSave else { return }   // QA 렌더용 임시 변경은 저장하지 않는다
    if let data = try? JSONEncoder().encode(settings) {
      UserDefaults.standard.set(data, forKey: settingsKey)
    }
  }

  /// QA 렌더 하네스 전용 — 저장 없이 설정 한 항목만 바꾼다(사용자 설정 오염 금지).
  func applyRenderOverride(ttsEngine: TTSEngine) {
    suppressSettingsSave = true
    settings.ttsEngine = ttsEngine
    suppressSettingsSave = false
  }

  /// QA 렌더·실검증용 — 웹 검색을 켠 상태로 **메모리에서만** 바꾼다(설정 저장 없음).
  func applyRenderOverride(webSearch enabled: Bool) {
    suppressSettingsSave = true
    settings.webSearchProvider = enabled ? .exa : .none
    suppressSettingsSave = false
  }

  /// QA 렌더·실검증용 — 대화를 **메모리에만** 바꾼다(저장 없음).
  func applyConversationForSelfTest(_ c: Conversation) {
    // 자가검증이 실제 history.json을 덮어쓰지 않게 이 실행 동안 저장을 막는다.
    suppressArchiveSaveForSelfTest = true
    core.open(c)
    conversation = core.conversation
  }

  /// QA 자가검증 전용 — true면 `syncArchive()`가 파일을 쓰지 않는다(사용자 기록 보호).
  var suppressArchiveSaveForSelfTest = false

  /// QA 실검증용 — 활성 프로바이더를 **메모리에서만** 바꾼다(설정 저장 없음).
  func applyRenderOverride(activeProviderID id: String) {
    suppressSettingsSave = true
    settings.activeProviderID = id
    suppressSettingsSave = false
  }

  /// QA 실검증용 — 프로바이더 **종류**로 활성 프로바이더를 고른다(예: Apple FM).
  func applyRenderOverride(providerType: LLMProviderType) {
    guard let p = settings.providers.first(where: { $0.type == providerType && $0.enabled })
      ?? settings.providers.first(where: { $0.type == providerType }) else { return }
    applyRenderOverride(activeProviderID: p.id)
  }

  // MARK: - 표시 정책 (메뉴바·Dock 중 최소 1개 유지)

  func setMenuBarIcon(_ visible: Bool) {
    var s = settings
    s.setMenuBarIcon(visible)
    settings = s
  }

  func setDockIcon(_ visible: Bool) {
    var s = settings
    s.setDockIcon(visible)
    settings = s
  }

  /// 현재 진입점 상태 안내 문구 (설정·Hub 공용)
  var visibilityHint: String {
    if !settings.showMenuBarIcon {
      return L("메뉴바 아이콘을 숨겼습니다. Dock 아이콘과 단축키로 열 수 있습니다.")
    }
    if settings.showDockIcon {
      return L("메뉴바와 Dock 양쪽에서 열 수 있습니다.")
    }
    return L("메뉴바 아이콘으로 열 수 있습니다. 단축키로도 호출됩니다.")
  }

  // MARK: - AI 빠른 설정 (대화 창 설정 탭 · 메뉴바 Hub 설정 탭 공용 상태)

  /// 마지막 AI 호출 결과 — 상태 카드에 표시(상주 요청 없이 결과만 보관)
  enum AICallState: Equatable {
    case none
    case ok
    case failed(String)
  }

  @Published var lastAICall: AICallState = .none
  /// 마지막 AI 오류의 **정확한 원인** 한 줄(상태 카드) — 성공하면 지운다.
  /// 예: `연결 거부 (-1004)`, `HTTP 401 · E-AND-AUTH-0004`
  @Published var lastAIErrorDetail: String?
  /// 활성 AI·모델 연결 테스트 진행 중
  @Published var testingProvider = false
  /// 연결 테스트 결과(응답 앞부분 또는 에러코드) — 비어 있으면 표시하지 않는다
  @Published var providerTestResult: String?
  @Published var modelOptions: [String] = []
  @Published var loadingModels = false
  @Published var modelNote: String?

  /// 모델 픽커 후보 — 저장된 모델명 + 조회해 온 목록
  var activeModelChoices: [String] {
    var list: [String] = []
    if let m = settings.activeProvider?.model, !m.isEmpty { list.append(m) }
    for m in modelOptions where !list.contains(m) { list.append(m) }
    return list
  }

  func setActiveProvider(_ id: String) {
    settings.activeProviderID = id
    modelOptions = []
    modelNote = nil
    providerTestResult = nil
    lastAIErrorDetail = nil
    lastAICall = .none
  }

  func setActiveModel(_ model: String) {
    guard let id = settings.activeProvider?.id,
          let i = settings.providers.firstIndex(where: { $0.id == id }) else { return }
    var list = settings.providers
    list[i].model = model
    settings.providers = list
    providerTestResult = nil
    lastAIErrorDetail = nil
    lastAICall = .none
  }

  /// 모델 목록 조회 — 사용자가 ⟳를 눌렀을 때만 요청한다(상주 요청 금지).
  func refreshModels() {
    guard let p = settings.activeProvider else {
      modelOptions = []; modelNote = L("활성 AI가 없습니다 (E-MAC-NET-0002)"); return
    }
    guard p.type != .appleFM else {
      modelOptions = []; modelNote = L("온디바이스 모델은 자동 선택됩니다"); return
    }
    guard let host = URL(string: p.baseURL) else {
      modelOptions = []; modelNote = L("주소가 올바르지 않습니다 (E-MAC-NET-0002)"); return
    }
    loadingModels = true
    modelNote = nil
    Task { @MainActor in
      defer { self.loadingModels = false }
      do {
        switch p.type {
        case .ollama:
          self.modelOptions = try await OllamaClient.listModels(host: host)
        case .openAICompatible:
          let key = p.secretID.isEmpty ? "" : (SecretStore.load(account: p.secretID) ?? "")
          self.modelOptions = try await OpenAIClient.listModels(baseURL: host, apiKey: key)
        case .appleFM:
          self.modelOptions = []
        }
        self.modelNote = self.modelOptions.isEmpty
          ? L("모델 목록이 비어 있습니다 (E-MAC-NET-0002)")
          : Lf("모델 %d개", self.modelOptions.count)
      } catch {
        self.modelOptions = []
        self.modelNote = L("모델 목록 조회 실패 (E-MAC-NET-0002)")
        NSLog("[ERROR] E-MAC-NET-0002 모델 목록 조회 실패: \(error)")
      }
    }
  }

  /// 선택한 AI·모델로 실제 질문(ping) 1건을 보내 연결을 확인한다.
  /// 설정 창의 '연결 테스트'(ProviderEditorSheet)와 같은 응답 경로를 쓴다.
  /// 응답 본문은 짧게만 화면에 남기고 로그에는 남기지 않는다.
  func testActiveProvider() {
    guard !testingProvider else { return }
    guard let p = settings.activeProvider else {
      providerTestResult = L("활성 AI가 없습니다 (E-MAC-NET-0002)")
      lastAIErrorDetail = L("활성 AI 없음")
      lastAICall = .failed("E-MAC-NET-0002")
      return
    }
    testingProvider = true
    providerTestResult = nil
    Task { @MainActor in
      defer { self.testingProvider = false }
      let started = Date()
      do {
        let reply = try await Self.reply(provider: p, prompt: "ping", history: [])
        let isError = reply.hasPrefix("(오류") || reply.hasPrefix("(Error")
        let elapsed = Date().timeIntervalSince(started)
        if isError {
          let code = Self.errorCode(in: reply)
          self.lastAICall = .failed(code)
          self.lastAIErrorDetail = Self.errorSummary(in: reply)
          self.providerTestResult = reply.count > 90 ? String(reply.prefix(90)) + "…" : reply
          NSLog("[QuickTalk] 연결 테스트 실패 (%@) %.1fs", code, elapsed)
        } else {
          self.lastAICall = .ok
          self.lastAIErrorDetail = nil
          let flat = reply
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          self.providerTestResult = Lf("응답: %@", flat.count > 60 ? String(flat.prefix(60)) + "…" : flat)
          NSLog("[QuickTalk] 연결 테스트 성공 %.1fs", elapsed)
        }
      } catch {
        let code = AIErrorText.code(for: error)
        let url = URL(string: p.baseURL)
        self.lastAICall = .failed(code)
        self.lastAIErrorDetail = AIErrorText.shortDetail(for: error)
        self.providerTestResult = Lf("실패 (%@): %@", code, AIErrorText.detail(for: error, url: url))
        NSLog("[QuickTalk] 연결 테스트 실패 (%@) — %@ %.1fs", code, AIErrorText.logLabel(for: error),
              Date().timeIntervalSince(started))
      }
    }
  }

  // MARK: - 상태 카드 (읽기 전용)

  var aiStatusText: String {
    switch lastAICall {
    case .none: return L("아직 호출 없음")
    case .ok: return L("정상")
    case .failed(let code): return Lf("실패 · %@", code)
    }
  }

  var aiStatusOK: Bool {
    if case .ok = lastAICall { return true }
    return false
  }

  var shortcutStatusOK: Bool { shortcutStatus[.invoke] ?? false }

  var voiceStatusText: String {
    settings.voiceEngine == .whisper
      ? (WhisperService.isReady(settings: settings) ? L("Whisper 준비됨") : L("Whisper 미지정"))
      : settings.voiceEngine.rawValue
  }

  var voiceStatusOK: Bool {
    settings.voiceEngine == .whisper ? WhisperService.isReady(settings: settings) : true
  }

  /// 오류 문구에서 에러코드만 추출 (없으면 네트워크 기본값)
  private static func errorCode(in text: String) -> String {
    guard let r = text.range(of: "E-MAC-[A-Z]+-[0-9]{4}", options: .regularExpression) else {
      return "E-MAC-NET-0001"
    }
    return String(text[r])
  }

  /// 오류 문구에서 `(오류 CODE) ` 접두어를 떼고 상태 카드용 문구로 만든다.
  /// 서버가 준 본문은 들어 있지 않고, 앱이 만든 원인 설명만 남는다.
  private static func errorSummary(in text: String) -> String {
    var body = text
    if let r = body.range(of: "^(?:\\(오류 |\\(Error )[^)]+\\)\\s*", options: .regularExpression) {
      body.removeSubrange(r)
    }
    body = body
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // 상태 카드는 여러 줄로 늘어날 수 있으므로 원인 설명을 자르지 않는다.
    // (서버 본문이 아니라 앱이 만든 고정 문구라 길이가 제한적이다)
    return body
  }

  /// 단축키로 새로 열 때의 세션 규칙 — 마지막 대화가 유지 시간(`shortcutSessionMinutes`)을
  /// 넘겼으면 지난 대화를 기록에 남기고 새로 시작한다. `0`(사용 안 함)이면 언제나 새 대화.
  func startShortcutSession() {
    guard !conversation.turns.isEmpty else { return }
    guard settings.continuesSession(lastActivity: conversation.updatedAt) else {
      NSLog("[QuickTalk] 단축키 세션 만료(%@) — 새 대화 시작", settings.sessionMinutesLabel)
      newConversation()
      return
    }
    NSLog("[QuickTalk] 단축키 세션 유지(%@) — 마지막 대화 이어서", settings.sessionMinutesLabel)
  }

  /// 새 대화 — 지금 대화는 **먼저 기록에 저장**하고 비운다(휘발 금지).
  /// 표시 언어가 바뀌었을 때 뷰를 다시 그리게 한다(번역표는 관찰 대상이 아니다).
  func languageDidChange() {
    objectWillChange.send()
  }

  func newConversation() {
    stopSpeaking()
    syncArchive()
    core.reset()
    conversation = core.conversation
    draft = ""; attached.removeAll()
    compactMessage = nil
  }
  // MARK: - 질문 되돌리기·다시 응답 (T-72)

  /// 질문을 입력창으로 되돌린다 — 그 질문과 이후 응답을 모두 지우고, 텍스트·첨부를 복원한다.
  func editQuestion(_ turn: Turn) {
    guard !isReplying, turn.role == .user else { return }
    restoreQuestion(turn, resend: false)
  }

  /// 같은 질문으로 다시 응답을 받는다 — 이후 대화를 지우고 방금 질문을 그대로 다시 보낸다.
  func regenerateAnswer(_ turn: Turn) {
    guard !isReplying, turn.role == .user else { return }
    restoreQuestion(turn, resend: true)
  }

  /// 어시스턴트 답변 바로 앞의 사용자 질문 — 웹 검색 재시도에 쓴다.
  func userTurn(before turnID: UUID) -> Turn? {
    guard let index = conversation.turns.firstIndex(where: { $0.id == turnID }) else { return nil }
    return conversation.turns[..<index].last(where: { $0.role == .user })
  }

  /// 답변이 "검색할 수 없다"고 밝혔고, 웹 검색이 준비되어 있으면 재시도 버튼을 보여 준다.
  func shouldOfferWebRetry(_ turn: Turn) -> Bool {
    guard settings.webSearchProvider != .none, webSearchKeyReady, !isReplying else { return false }
    guard turn.role == .assistant, !turn.text.isEmpty else { return false }
    guard (turn.sources ?? []).isEmpty else { return false }
    guard WebSearchQuery.looksLikeSearchRefusal(turn.text) else { return false }
    return userTurn(before: turn.id) != nil
  }

  /// 같은 질문을 웹 검색 강제로 다시 보낸다 — 이후 턴은 지우고 새 답변을 만든다.
  func retryWithWebSearch(_ turn: Turn) {
    guard shouldOfferWebRetry(turn), let question = userTurn(before: turn.id) else { return }
    forceWebSearch = true
    NSLog("[QuickTalk] 웹 검색 재시도 — 이전 답변을 되돌리고 같은 질문을 검색 강제로 전송")
    regenerateAnswer(question)
  }

  private func restoreQuestion(_ turn: Turn, resend: Bool) {
    guard let restored = core.rewind(toUserTurnID: turn.id) else { return }
    conversation = core.conversation
    draft = restored.text
    attached = restored.attachments.map { a in
      PendingAttachment(name: a.name,
                        url: a.path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
                        kind: a.kind)
    }
    searchFocus = nil
    compactMessage = nil
    lastAICall = .none
    lastAIErrorDetail = nil
    composerFocusToken = UUID()
    syncArchive()
    if resend { send(allowCommands: false) }
  }

  /// 보관(만료 없이 유지) 토글
  func togglePin() {
    core.togglePin()
    conversation = core.conversation
    syncArchive()
  }
  /// 모든 대화 기록(자동 저장분 + 보관분). 화면에는 `syncArchive`/`loadArchive`로 반영된다.
  @Published var archive: [Conversation] = []

  func loadArchive() {
    var list = PersistenceService.load(keepDays: settings.keepDays)
    if !conversation.turns.isEmpty || conversation.pinned {
      list.removeAll { $0.id == conversation.id }
      list.insert(conversation, at: 0)
    }
    archive = ConversationHistory.ordered(list)
  }

  /// 앱 시작 시 마지막 대화를 이어서 연다(2026-10-20 "언제나 새 대화" 수정).
  func restoreLastConversation() {
    guard conversation.turns.isEmpty,
          let latest = ConversationHistory.mostRecent(archive) else { return }
    core.open(latest)
    conversation = core.conversation
    NSLog("[QuickTalk] 마지막 대화 복원 — %d턴 pinned=%@",
          conversation.turns.count, conversation.pinned ? "Y" : "N")
    // 앱을 다시 켰을 때 이미 예산을 넘었으면 백그라운드로 정리한다(첫 답변 지연 방지).
    startAutoCompact(convID: conversation.id)
  }

  /// 현재 대화를 기록에 반영하고 파일에 쓴다 — 핀 여부와 무관(모든 대화 자동 저장).
  func syncArchive() {
    guard !suppressArchiveSaveForSelfTest else { return }
    archive.removeAll { $0.id == conversation.id }
    if !conversation.turns.isEmpty || conversation.pinned {
      archive.insert(conversation, at: 0)
    }
    archive = ConversationHistory.ordered(archive)
    do {
      try PersistenceService.save(archive)
    } catch {
      NSLog("[WARN] E-MAC-RENDER-0001 대화 기록 저장 실패: %@", String(describing: error))
    }
  }

  /// 대화방 제목 변경 — 대화 헤더·보관함 공용.
  /// 현재 대화면 코어에 반영하고, 보관함 목록·파일에도 즉시 저장한다. 빈 제목은 무시.
  func renameConversation(id: UUID, to newTitle: String) {
    let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    if conversation.id == id {
      core.rename(to: t)
      conversation = core.conversation
    }
    if let i = archive.firstIndex(where: { $0.id == id }) {
      archive[i].rename(to: t)
    }
    syncArchive()
  }

  func deleteConversation(_ c: Conversation) {
    archive.removeAll { $0.id == c.id }
    try? PersistenceService.save(archive)
    // 현재 대화를 지웠다면 그 자리에서 비운다(syncArchive로 되살아나지 않게)
    if conversation.id == c.id {
      core.reset()
      conversation = core.conversation
      draft = ""; attached.removeAll()
    }
  }

  func clearArchive() {
    archive.removeAll()
    try? PersistenceService.save(archive)
  }

  /// 보관함에서 대화를 연다. `searching`이 있으면 그 검색어와 일치하는 첫 턴으로 포커스를 요청한다.
  func openConversation(_ c: Conversation, searching query: String = "") {
    core.open(c)
    conversation = core.conversation
    compactMessage = nil
    if let turn = c.firstTurn(matching: query) {
      searchFocus = SearchFocusRequest(conversationID: c.id, turnID: turn.id, query: query)
    } else {
      searchFocus = nil
    }
    startAutoCompact(convID: c.id)
  }

  // MARK: - 음성 (엔진별 분기)
  func toggleVoice() {
    // 받아쓰기 시작 전에 낭독을 멈춘다(스피커 소리가 마이크로 들어가지 않게)
    if !voiceRecording { stopSpeaking() }
    switch settings.voiceEngine {
    case .apple:
      speech.toggle()
    case .whisper:
      toggleWhisperRecord()
    }
  }

  /// 읽어주기 — 같은 응답을 읽는 중이면 **중지**, 다른 응답이면 그 응답으로 바꿔 읽는다.
  func speak(_ text: String, turnID: UUID? = nil) {
    guard !text.isEmpty else { return }
    if isSpeaking, turnID == nil || speakingTurnID == turnID {
      stopSpeaking()
      return
    }
    // 엔진을 바꿔 읽거나 다른 답변으로 넘어갈 때 — 이전 소리를 반드시 끊는다
    stopSpeaking()
    speakingTurnID = turnID
    switch settings.ttsEngine {
    case .edge: edgeSpeech.speak(text)
    case .piper: piperSpeech.speak(text)
    case .apple: speech.speak(text)
    }
  }

  /// 읽어주기 중지(헤더·Hub·메시지 버튼 공용)
  func stopSpeaking() {
    speech.stopSpeaking()
    edgeSpeech.stop()
    piperSpeech.stop()
    speakingTurnID = nil
  }

  /// 설정 창 '미리 듣기' — 지금 고른 엔진·목소리·속도로 샘플을 읽는다
  func previewVoice() {
    stopSpeaking()
    switch settings.ttsEngine {
    case .edge: edgeSpeech.previewVoice()
    case .piper: piperSpeech.previewVoice()
    case .apple: speech.previewVoice()
    }
  }

  /// 음성 설정을 서비스에 넘긴다(받아쓰기 언어·읽어주기 목소리/속도)
  private func applySpeechSettings() {
    speech.configure(locale: settings.appleSpeechLocale,
                     voice: settings.ttsVoiceID,
                     ttsLanguage: settings.ttsLanguage,
                     rate: settings.ttsRate)
    edgeSpeech.configure(voice: settings.edgeVoice,
                         rate: settings.ttsRate,
                         binary: settings.edgeBinaryPath)
    piperSpeech.configure(rate: settings.ttsRate,
                          model: settings.piperModelPath,
                          binary: settings.piperBinaryPath)
  }

  private var whisperURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("quicktalk-voice.wav")
  }

  private func toggleWhisperRecord() {
    if let rec = whisperRecorder, rec.isRecording {
      rec.stop()
      whisperRecorder = nil
      voiceRecording = false
      transcribeWhisper()
      return
    }
    guard WhisperService.isReady(settings: settings) else {
      NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 미준비: \(WhisperService.status(settings: settings))")
      draft = L("(Whisper 미준비) ") + WhisperService.status(settings: settings)
      return
    }
    let fmt = [AVFormatIDKey: Int(kAudioFormatLinearPCM),
               AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false] as [String: Any]
    do {
      whisperRecorder = try AVAudioRecorder(url: whisperURL, settings: fmt)
      whisperRecorder?.record()
      voiceRecording = true
    } catch {
      NSLog("[ERROR] E-MAC-AUDIO-0001 녹음 시작 실패: \(error)")
    }
  }

  private func transcribeWhisper() {
    Task { @MainActor in
      do {
        draft = try await WhisperService.transcribe(wavURL: whisperURL, settings: settings)
      } catch {
        NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 전사 실패: \(error)")
        draft = L("(전사 실패 E-MAC-AUDIO-0001)")
      }
    }
  }
  func send(allowCommands: Bool = true) {
    stopSpeaking()
    // 응답 대기 중 중복 전송 금지 — 답이 섞이지 않게 한다(입력독의 ↑도 비활성)
    guard !isReplying else {
      NSLog("[QuickTalk] 응답 대기 중 — 중복 전송 무시")
      return
    }
    // 보조 명령 — 일반 사용자는 자동 정리만 쓰면 된다. `/compact`는 즉시 정리.
    let command = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if allowCommands, command == "/compact" {
      draft = ""
      compactNow()
      return
    }
    do {
      let pending = attached                       // 전송 직후 목록을 비우므로 미리 잡아 둔다
      // 경로까지 남긴다 — 보낸 뒤 말풍선에 썸네일·미리보기를 다시 그리기 위해
      let atts = pending.map { Attachment(name: $0.name, kind: $0.kind, path: $0.url?.path) }
      let prompt = draft
      try core.submit(text: prompt, attachments: atts)
      conversation = core.conversation
      draft = ""; attached.removeAll()
      syncArchive()                      // 사용자 메시지도 바로 기록(앱이 꺼져도 남는다)
      // 한글 IME: 전송 직후 조합 커밋이 입력창으로 되돌아오는 경우가 있어 잠시 방어한다
      suppressEcho(of: prompt)
      isReplying = true
      replyStartedAt = Date()
      let convID = conversation.id
      replyTask = Task { @MainActor in
        // 응답까지 걸린 시간 — 모델 호출 구간만 잰다(첨부 읽기 제외)
        var callStarted = Date()
        defer {
          self.isReplying = false
          self.replyStartedAt = nil
          self.streamingTurnID = nil
          self.isSearching = false
          self.replyTask = nil
        }
        // 첨부 "내용"은 여기서 읽는다 — 텍스트 파일은 본문 인라인, 이미지는 data URL로 실린다
        let outgoing = await Self.loadAttachments(pending)
        if !outgoing.isEmpty {
          NSLog("[QuickTalk] 첨부 전송 준비 — %@", AttachmentLoader.summary(outgoing))
        }
        guard self.conversation.id == convID else { return }
        // 사용자가 [중지]를 눌렀으면 여기서 멈춘다(모델 호출 없이 종료).
        if Task.isCancelled { return }
        guard let provider = self.settings.activeProvider else {
          self.compactMessage = L("활성 AI가 없습니다. 설정 > AI에서 프로바이더를 켜 주세요.")
          self.lastAICall = .failed("E-MAC-MODEL-0002")
          self.lastAIErrorDetail = L("활성 AI가 없습니다.")
          return
        }
        // 이번 질문은 `prompt`로 따로 싣는다 — 기록에서 사용자 턴까지 빼야 같은 질문이 두 번 들어가지 않는다
        // 요약이 있으면 경계 이후만 원문으로 싣고, 요약은 프롬프트 앞에 고정한다.
        // 예산을 넘는 장문 대화는 오래된 기록부터 요청에서 제외한다(원문은 저장소에 유지).
        let attachmentTokens = outgoing.reduce(0) { sum, a in
          sum + ConversationMemory.estimateTokens(a.name) + (a.kind == .image ? 256 : 0)
        }
        let ws = self.settings
        // 로컬 Ollama는 프롬프트가 길수록 첫 토큰이 늦다 — 검색 결과 수·본문 길이를 먼저 줄인다.
        // (Apple FM·원격은 설정값 그대로 — 이 절약은 Ollama 전용이다)
        let searchLimits = WebSearchPromptLimits.limits(resultCount: ws.webSearchResultCount,
                                                        maxCharacters: ws.webSearchMaxCharacters,
                                                        provider: provider)
        if searchLimits.resultCount != ws.webSearchResultCount
            || searchLimits.maxCharacters != ws.webSearchMaxCharacters {
          NSLog("[QuickTalk] Ollama 문맥 절약 — 검색 %d건·%d자로 축소(설정 %d건·%d자)",
                searchLimits.resultCount, searchLimits.maxCharacters,
                ws.webSearchResultCount, ws.webSearchMaxCharacters)
        }
        // 공통 메모리 — 이 대화에서 끄지 않았고 전역 설정이 켜져 있을 때만.
        // 대화 요약보다 **앞**에 둔다(변하지 않는 사용자 사실이 먼저 보이게).
        let globalMemory: GlobalMemoryPrompt = self.commonMemoryActive
          ? GlobalMemory.prompt(self.memoryEntries, query: prompt,
                                mode: ws.globalMemoryMode,
                                budget: ws.globalMemoryBudgetTokens)
          : .empty
        let conversationPrefix = Self.memoryPromptPrefix(self.conversation)
        let memoryPrefix = globalMemory.text + conversationPrefix
        if !globalMemory.isEmpty {
          NSLog("[QuickTalk] 공통 메모리 %d개 주입 (약 %d토큰)",
                globalMemory.included.count, globalMemory.tokens)
        }
        let fitted = ConversationMemory.fitHistory(self.conversation,
                                                   prompt: prompt,
                                                   provider: provider,
                                                   attachmentTokens: attachmentTokens,
                                                   extraTokens: globalMemory.tokens
                                                     + (ws.webSearchEnabled ? 400 : 0))
        let history = fitted.history
        if fitted.dropped > 0 {
          self.compactMessage = Lf("모델 예산을 넘어 이전 메시지 %d개를 이번 요청에서 제외했습니다. 원문은 그대로 남아 있습니다.",
                                   fitted.dropped)
          NSLog("[QuickTalk] 예산 초과 — 이번 요청에서 이전 턴 %d개 제외", fitted.dropped)
        }
        // 검색 컨텍스트는 크기 제한이 없다(설정 2,000자 × 결과 수). 작은 컨텍스트 모델
        // (Apple FM 등)에서 기록을 모두 비워도 넘치지 않도록 입력 예산의 1/3로 자른다.
        func cappedSearchContext(_ text: String) -> String {
          guard !text.isEmpty else { return "" }
          let cap = WebSearchPromptLimits.contextCap(for: provider)
          guard ConversationMemory.estimateTokens(text) > cap else { return text }
          NSLog("[QuickTalk] 검색 컨텍스트가 커서 %d토큰으로 줄임", cap)
          return GlobalMemory.clip(text, toTokens: cap)
        }
        // ── 웹 검색 (PLAN_v0.14) — 답변 생성 **전에** 1회, 실패해도 답변은 계속한다 ──
        var modelPrompt = memoryPrefix + prompt
        var sources: [TurnSource] = []
        var searchNote: String?
        /// 실제로 프롬프트에 들어간 검색 컨텍스트 토큰 — 기록 예산을 정확히 다시 맞춘다.
        var searchContextTokens = 0
        /// 툴 콜링이 검색 없이 바로 답한 경우 — 두 번째 모델 호출을 건너뛴다.
        var precomputedAnswer: String?
        let forced = self.forceWebSearch
        self.forceWebSearch = false

        // P3-a) 툴 콜링 — 모델이 `web_search`를 직접 호출한다. OpenAI 호환에서만 시도하고,
        // 프록시가 tools를 모르면(400) 아래 기존 주입 경로로 조용히 폴백한다.
        var handledByTool = false
        var toolFellBack = false
        if ws.webSearchEnabled, ws.webSearchMode == .toolCalling,
           provider.type == .openAICompatible, !forced {
          self.isSearching = true
          let plan = await self.planWebToolCall(provider: provider,
                                                prompt: memoryPrefix + prompt,
                                                history: history,
                                                attachments: outgoing)
          self.isSearching = false
          switch plan {
          case .search(let results):
            handledByTool = true
            if results.isEmpty {
              searchNote = L("⚠️ 모델이 검색을 요청했지만 결과가 없습니다 — 모델 지식으로 답합니다.")
            } else {
              let context = cappedSearchContext(WebSearchContext.build(
                results: results,
                maxCharacters: searchLimits.maxCharacters,
                limit: searchLimits.resultCount))
              searchContextTokens = ConversationMemory.estimateTokens(context)
              modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
              sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
              NSLog("[QuickTalk] 툴 콜링 검색 %d건 → 프롬프트 주입", sources.count)
            }
          case .answer(let text):
            handledByTool = true
            precomputedAnswer = text
            NSLog("[QuickTalk] 툴 콜링 — 검색 없이 모델이 직접 답변 (%d자)", text.count)
          case .unsupported(let detail):
            toolFellBack = true
            searchNote = detail
            NSLog("[WARN] E-MAC-TOOL-0001 툴 콜링 미지원 → 주입 폴백")
          case .failed(let detail):
            handledByTool = true
            searchNote = detail
            NSLog("[WARN] %@ 툴 콜링 요청 실패 → 검색 없이 답변",
                  WebToolError.requestFailed.code)
          }
        }

        // P3-b) `/answer` 또는 기존 주입 — "필요할 때만"은 모델 Y/N 판정으로 정한다.
        // 🌐를 켠 질문은 판정을 건너뛰고 반드시 검색한다.
        var needsSearch = false
        if !handledByTool {
          needsSearch = WebSearchQuery.shouldSearch(provider: ws.webSearchProvider, forced: forced)
          // 툴 콜링은 OpenAI 호환에서만 시도한다 — 다른 프로바이더에서는 주입 판정으로 폴백.
          let toolModeUnavailable = ws.webSearchMode == .toolCalling
            && provider.type != .openAICompatible
          if !needsSearch, ws.webSearchEnabled,
             (ws.webSearchMode != .toolCalling || toolFellBack || toolModeUnavailable) {
            needsSearch = await self.decidesToSearch(prompt, history: history)
          }
        }
        if !handledByTool, needsSearch {
          self.isSearching = true
          if ws.webSearchMode == .answer {
            // Exa `/answer` — 실패하면 같은 질문으로 일반 검색을 한 번 더 시도한다.
            let answered = await self.answerWeb(query: prompt)
            self.isSearching = false
            switch answered {
            case .success(let result):
              if result.isEmpty {
                searchNote = L("⚠️ 웹 답변 결과가 비어 있습니다 — 모델 지식으로 답합니다.")
              } else {
                let context = cappedSearchContext(ExaAnswer.context(result,
                                                                    limit: searchLimits.resultCount))
                searchContextTokens = ConversationMemory.estimateTokens(context)
                modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
                sources = result.sources
                NSLog("[QuickTalk] /answer 인용 %d건 → 프롬프트 주입", sources.count)
              }
            case .failure(let error):
              searchNote = error.userText
              NSLog("[ERROR] %@ /answer 실패 → 일반 검색 폴백", error.code)
              let fallback = await self.searchWeb(query: prompt)
              if case .success(let results) = fallback, !results.isEmpty {
                let context = cappedSearchContext(WebSearchContext.build(
                  results: results,
                  maxCharacters: searchLimits.maxCharacters,
                  limit: searchLimits.resultCount))
                searchContextTokens = ConversationMemory.estimateTokens(context)
                modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
                sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
              }
            }
          } else {
            let outcome = await self.searchWeb(query: prompt)
            self.isSearching = false
            switch outcome {
            case .success(let results):
              if results.isEmpty {
                searchNote = L("⚠️ 웹 검색 결과가 없습니다 — 모델 지식으로 답합니다.")
              } else {
                let context = cappedSearchContext(WebSearchContext.build(
                  results: results,
                  maxCharacters: searchLimits.maxCharacters,
                  limit: searchLimits.resultCount))
                searchContextTokens = ConversationMemory.estimateTokens(context)
                modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
                sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
                NSLog("[QuickTalk] 웹 검색 %d건 → 프롬프트 주입", sources.count)
              }
            case .failure(let error):
              // 검색어·본문은 로그에 남기지 않는다(코드만)
              searchNote = error.userText
              NSLog("[ERROR] %@ 웹 검색 실패", error.code)
            }
          }
        }
        // 검색 중 사용자가 다른 대화방으로 옮겼으면 이 답변은 버린다(다른 방에 섞이지 않게).
        guard self.conversation.id == convID else { return }
        // 초기 400토큰 예약보다 검색 컨텍스트가 크면 기록을 다시 맞춘다.
        // (검색은 기록 fitting 뒤에 일어나므로 실제 컨텍스트 크기를 그때 알 수 있다.)
        var finalHistory = history
        if searchContextTokens > 400 {
          let refit = ConversationMemory.fitHistory(
            self.conversation, prompt: prompt, provider: provider,
            attachmentTokens: attachmentTokens,
            extraTokens: globalMemory.tokens + searchContextTokens)
          finalHistory = refit.history
          if refit.dropped > fitted.dropped {
            self.compactMessage = Lf("모델 예산을 넘어 이전 메시지 %d개를 이번 요청에서 제외했습니다. 원문은 그대로 남아 있습니다.",
                                     refit.dropped)
            NSLog("[QuickTalk] 검색 컨텍스트로 기록 %d개 추가 제외", refit.dropped - fitted.dropped)
          }
        }
        callStarted = Date()
        // 스트리밍 버블 — 첫 델타 전까지는 아래 점 애니메이션이 보인다
        if Task.isCancelled { return }     // 검색·판정 중에 [중지]를 누른 경우
        let aid = self.core.beginAssistantTurn()
        self.conversation = self.core.conversation
        self.streamingTurnID = aid
        // 첨부 경고(줄임·미전송)는 델타보다 먼저 붙인다 — 기존 `reply`와 같은 순서
        if let searchNote {
          self.core.appendStreaming(searchNote + "\n\n", to: aid)
          self.conversation = self.core.conversation
        }
        let warnings = AttachmentLoader.warnings(outgoing)
        if !warnings.isEmpty {
          self.core.appendStreaming(warnings, to: aid)
          self.conversation = self.core.conversation
        }
        var buffer = ""
        var lastFlush = Date.distantPast
        let flush: (Bool) -> Void = { force in
          guard force || Date().timeIntervalSince(lastFlush) >= 0.08 else { return }
          guard !buffer.isEmpty else { return }
          guard self.conversation.id == convID else { buffer = ""; return }
          self.core.appendStreaming(buffer, to: aid)
          buffer = ""
          lastFlush = Date()
          self.conversation = self.core.conversation
        }
        do {
          guard let p = self.settings.activeProvider else {
            throw QuickTalkError.providerNotConfigured()
          }
          let reply: String
          if let precomputedAnswer {
            // 툴 콜링이 검색 없이 답한 경우 — 그대로 표시한다(스트리밍 없음).
            reply = precomputedAnswer
            self.core.appendStreaming(precomputedAnswer, to: aid)
            self.conversation = self.core.conversation
          } else {
            reply = try await Self.streamReplyWithFallback(
              settings: self.settings, provider: p, prompt: modelPrompt,
              history: finalHistory,
              attachments: outgoing,
              onDelta: { delta in
                buffer += delta
                flush(false)
              })
          }
          flush(true)
          guard self.conversation.id == convID else { return }
          let current = self.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
          // 오류 문구는 표시 언어에 따라 "(오류 …)" 또는 "(Error …)"로 시작한다
          let isError = reply.hasPrefix("(오류") || reply.hasPrefix("(Error")
          if isError {
            // 재시도 사다리가 델타 대신 오류 문자열을 돌려준 경우
            self.core.setAssistantText(current.isEmpty ? reply : current + "\n\n" + reply, id: aid)
          } else if current.isEmpty {
            // 스트리밍을 지원하지 않는 경로(기본 구현) — 한 번에 채운다
            self.core.setAssistantText(reply, id: aid)
          }
          self.core.finishAssistantTurn(aid, elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000),
                                        sources: sources.isEmpty ? nil : sources)
          self.conversation = self.core.conversation
          self.syncArchive()
          // 답변을 마친 뒤 **백그라운드로** 정리한다 — 현재 답변 지연을 만들지 않는다.
          if !isError { self.startAutoCompact(convID: convID) }
          self.lastAICall = isError ? .failed(Self.errorCode(in: reply)) : .ok
          self.lastAIErrorDetail = isError ? Self.errorSummary(in: reply) : nil
        } catch {
          // 사용자가 [중지]를 누른 경우 — 오류가 아니다. 부분 출력은 남기고 안내만 덧붙인다.
          if Task.isCancelled || error is CancellationError
              || (error as? URLError)?.code == .cancelled {
            flush(true)
            let current = self.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
            if current.isEmpty {
              self.core.setAssistantText(L("응답을 중지했습니다."), id: aid)
            } else {
              self.core.appendStreaming(L("\n\n⏹ 중지됨"), to: aid)
            }
            self.core.finishAssistantTurn(aid,
                                          elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000),
                                          sources: sources.isEmpty ? nil : sources)
            self.conversation = self.core.conversation
            self.syncArchive()
            NSLog("[QuickTalk] 사용자 중지 — 응답 취소(부분 %d자)", current.count)
            return
          }
          // 실패는 코드 + **정확한 원인**으로 남긴다 — 연결 거부·시간 초과·오프라인·TLS가
          // 모두 NET-0001로 뭉개지지 않게(URLError 상세는 AIErrorText가 만든다).
          flush(true)
          let code = AIErrorText.code(for: error)
          let url = self.settings.activeProvider.flatMap { URL(string: $0.baseURL) }
          let text = AIErrorText.userText(for: error, url: url)
          NSLog("[ERROR] %@ LLM 호출 실패 — %@", code, AIErrorText.logLabel(for: error))
          let current = self.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
          self.core.setAssistantText(current.isEmpty ? text : current + "\n\n" + text, id: aid)
          self.core.finishAssistantTurn(aid, elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000))
          self.conversation = self.core.conversation
          self.syncArchive()
          self.lastAICall = .failed(code)
          self.lastAIErrorDetail = AIErrorText.shortDetail(for: error)
        }
      }
    } catch {
      // 사용자 [중지]로 취소된 경우는 오류가 아니다 — 조용히 끝낸다.
      if Task.isCancelled || error is CancellationError {
        print("[QuickTalk] 사용자 중지 — 전송 준비 취소")
        return
      }
      // [ERROR] E-MAC-MODEL-0001 + 메시지 매핑. 무음 실패 금지
      print("[ERROR] E-MAC-MODEL-0001 빈 제출 또는 첨부 오류: \(error)")
    }
  }

  /// 진행 중인 응답을 사용자가 중지한다.
  ///
  /// 로컬 Ollama는 첫 토큰까지 수 분 걸릴 수 있어(문맥 처리 30~90초 + 모델 로드) 300초 동안
  /// 입력독이 잠긴다. 그 사이 모델이 멈춘 것처럼 보여도 빠져나갈 수단이 없었다 — 이 버튼이 그 출구다.
  /// 부분 출력이 있으면 남기고, 없으면 "응답을 중지했습니다."만 남긴다(예비 모델로 넘어가지 않는다).
  func cancelReply() {
    guard isReplying else { return }
    NSLog("[QuickTalk] 사용자 중지 요청 — 진행 중인 응답 취소")
    replyTask?.cancel()
    replyTask = nil
    isReplying = false
    replyStartedAt = nil
    streamingTurnID = nil
    isSearching = false
  }

  // MARK: - 대화 기억 정리 (T-71)

  /// 요청에 실을 기록 — 요약 경계 이후의 원문만 남기고, 방금 추가된 사용자 턴은 뺀다.
  static func requestHistory(_ conversation: Conversation) -> [Turn] {
    ConversationMemory.requestHistory(conversation)
  }

  /// 요약을 프롬프트 앞에 고정한다 — Apple FM의 6턴 제한에 잘리지 않게.
  static func memoryPromptPrefix(_ conversation: Conversation) -> String {
    ConversationMemory.memoryPromptPrefix(conversation)
  }

  // MARK: - 공통 메모리 (PLAN_v0.16)

  /// 이 대화에서 공통 메모리를 쓰는가 — 전역 설정 + 대화별 토글.
  var commonMemoryActive: Bool {
    settings.globalMemoryEnabled && conversation.commonMemoryDisabled != true
  }

  /// 이 대화만 공통 메모리 주입을 끄거나 켠다.
  func setCommonMemory(enabledForConversation on: Bool) {
    core.setCommonMemoryDisabled(!on)
    conversation = core.conversation
    syncArchive()
  }

  /// 항목 추가·수정 — 같은 ID가 있으면 덮어쓰고 `updatedAt`을 갱신한다.
  func upsertMemory(_ entry: GlobalMemoryEntry) {
    var copy = entry
    copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.content = copy.content.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.tags = GlobalMemoryEntry.normalizeTags(copy.tags.joined(separator: ","))
    copy.updatedAt = Date()
    if let i = memoryEntries.firstIndex(where: { $0.id == copy.id }) {
      memoryEntries[i] = copy
    } else {
      memoryEntries.append(copy)
    }
  }

  func deleteMemory(_ id: UUID) {
    memoryEntries.removeAll { $0.id == id }
  }

  func setMemoryEnabled(_ id: UUID, _ on: Bool) {
    guard let i = memoryEntries.firstIndex(where: { $0.id == id }) else { return }
    // 사용 여부는 내용이 아니므로 updatedAt을 바꾸지 않는다(임베딩 캐시 유지·정렬 안정).
    memoryEntries[i].enabled = on
  }

  /// 목록 순서 변경(위/아래) — 프롬프트에 들어가는 순서이기도 하다.
  func moveMemory(_ id: UUID, by offset: Int) {
    guard let i = memoryEntries.firstIndex(where: { $0.id == id }) else { return }
    let j = i + offset
    guard memoryEntries.indices.contains(j) else { return }
    memoryEntries.swapAt(i, j)
  }

  /// JSON 내보내기 — 사용자가 고른 경로에 원자적으로 쓴다.
  func exportMemory(to url: URL) {
    do {
      try GlobalMemoryFile.save(memoryEntries, to: url)
      memoryNotice = Lf("메모리 %d개를 내보냈습니다.", memoryEntries.count)
    } catch {
      memoryNotice = Lf("메모리 내보내기에 실패했습니다: %@", error.localizedDescription)
      NSLog("[ERROR] E-MAC-MEM-0002 공통 메모리 내보내기 실패")
    }
  }

  /// JSON 가져오기 — 같은 ID는 건너뛰고 새 항목만 추가한다.
  func importMemory(from url: URL) {
    do {
      let data = try Data(contentsOf: url)
      let imported = try GlobalMemoryFile.decode(data)
      let merged = GlobalMemoryFile.merge(memoryEntries, with: imported)
      memoryNotice = nil
      memoryEntries = merged.entries
      // didSet 저장이 실패하면 그 안내를 덮지 않는다.
      if memoryNotice == nil {
        memoryNotice = Lf("메모리 %d개를 가져왔습니다.", merged.added)
      }
    } catch {
      memoryNotice = Lf("메모리 가져오기에 실패했습니다: %@", error.localizedDescription)
      NSLog("[ERROR] E-MAC-MEM-0003 공통 메모리 가져오기 실패")
    }
  }

  @discardableResult
  private func saveMemory() -> Bool {
    guard !suppressMemorySave else { return true }
    do {
      try GlobalMemoryFile.save(memoryEntries)
      return true
    } catch {
      NSLog("[ERROR] E-MAC-MEM-0004 공통 메모리 저장 실패")
      memoryNotice = L("메모리를 저장하지 못했습니다.")
      return false
    }
  }

  /// QA 렌더 전용 — 저장 없이 메모리를 메모리에만 넣는다.
  func applyRenderOverride(memory entries: [GlobalMemoryEntry]) {
    suppressMemorySave = true
    memoryEntries = entries
    suppressMemorySave = false
  }

  /// Apple FM은 4K 예산이라 최근 원문을 4개까지만 남긴다(사용자 설정이 더 커도).
  private func effectiveKeepTurns(for provider: LLMProviderConfig) -> Int {
    let requested = max(2, settings.compactKeepTurns)
    return provider.type == .appleFM ? min(requested, 4) : requested
  }

  /// `/compact` — 임계치와 무관하게 지금 정리한다(전문가용 보조 명령).
  func compactNow() {
    // 답변 중에는 정리하지 않는다 — 스트리밍 중인 반쪽 답변을 요약에 넣지 않기 위해서다.
    guard !isCompacting, !isReplying else { return }
    if conversation.autoCompactPaused {
      core.resumeAutoCompact()
      conversation = core.conversation
    }
    runCompaction(conversation: conversation, manual: true)
  }

  /// 답변을 마친 뒤 호출 — 예산의 70%를 넘었을 때만 백그라운드로 정리한다.
  func startAutoCompact(convID: UUID) {
    guard settings.autoCompact, !isCompacting else { return }
    guard conversation.id == convID, !conversation.autoCompactPaused else { return }
    guard let provider = settings.activeProvider else { return }
    let keep = effectiveKeepTurns(for: provider)
    guard ConversationMemory.shouldCompact(conversation, provider: provider, keepTurns: keep) else {
      return
    }
    runCompaction(conversation: conversation, manual: false)
  }

  /// 정리 실행 — 원문은 그대로 두고 `summary`만 갱신한다(실패하면 아무것도 바꾸지 않는다).
  private func runCompaction(conversation target: Conversation, manual: Bool) {
    guard let provider = settings.activeProvider else {
      if manual { compactMessage = L("활성 AI가 없습니다. 설정 > AI에서 프로바이더를 켜 주세요.") }
      return
    }
    let keep = effectiveKeepTurns(for: provider)
    let boundary = ConversationMemory.boundaryIndex(turnCount: target.turns.count, keepTurns: keep)
    guard boundary >= 2 else {
      if manual { compactMessage = L("정리할 이전 대화가 없습니다.") }
      return
    }
    let previousBoundary = target.summaryBoundaryIndex
    let start = previousBoundary.map { $0 + 1 } ?? 0
    guard start < boundary else {
      if manual { compactMessage = L("이미 최근 대화까지 정리되어 있습니다.") }
      return
    }
    let oldTurns = Array(target.turns[start..<boundary])
    let through = target.turns[boundary - 1].id
    let previous = target.activeSummary
    let convID = target.id
    isCompacting = true
    compactingConversationID = convID
    compactMessage = nil
    Task { @MainActor in
      defer {
        self.isCompacting = false
        self.compactingConversationID = nil
      }
      do {
        let summary = try await Self.makeSummary(provider: provider, previous: previous, turns: oldTurns)
        // 그 사이 대화가 바뀌었거나 사용자가 요약을 해제했으면 적용하지 않는다(다른 방에 섞이지 않게)
        guard self.conversation.id == convID,
              !self.conversation.autoCompactPaused,
              self.conversation.turns.contains(where: { $0.id == through }) else { return }
        self.core.applySummary(summary, through: through)
        self.conversation = self.core.conversation
        self.syncArchive()
        NSLog("[QuickTalk] 대화 정리 — %d턴 → 요약 %d자 (%@)",
              oldTurns.count, summary.count, provider.type.rawValue)
      } catch {
        let code = AIErrorText.code(for: error)
        NSLog("[ERROR] %@ 대화 정리 실패", code)
        if manual { self.compactMessage = Lf("대화 정리에 실패했습니다 (%@)", code) }
      }
    }
  }

  /// 요약 생성 — 긴 기록은 청크로 나눠 **기존 요약 + 다음 부분**을 반복 갱신한다(롤링 요약).
  /// Apple FM은 4K 컨텍스트라 작은 청크, 원격·Ollama는 큰 청크를 쓴다.
  nonisolated static func makeSummary(provider: LLMProviderConfig,
                                      previous: String?,
                                      turns: [Turn]) async throws -> String {
    guard !turns.isEmpty else {
      throw QuickTalkError.detailed(L("정리할 대화가 없습니다."), code: "E-MAC-MEM-0001")
    }
    let limit = ConversationMemory.summaryLimit(for: provider)
    let chunkLimit = ConversationMemory.chunkLimit(for: provider)
    let full = ConversationMemory.transcript(turns)
    let pieces = ConversationMemory.chunks(full, maxCharacters: chunkLimit)
    guard !pieces.isEmpty else {
      throw QuickTalkError.detailed(L("대화 요약을 만들지 못했습니다."), code: "E-MAC-MEM-0001")
    }
    var summary = previous
    for piece in pieces {
      let prompt = ConversationMemory.summaryPrompt(previous: summary, transcript: piece,
                                                    maxCharacters: limit)
      let raw = try await UIStore.reply(provider: provider, prompt: prompt, history: [])
      guard let clipped = ConversationMemory.clipSummary(raw, maxCharacters: limit) else {
        throw QuickTalkError.detailed(L("대화 요약이 비어 있습니다."), code: "E-MAC-MEM-0001")
      }
      summary = clipped
    }
    guard let summary, !summary.isEmpty else {
      throw QuickTalkError.detailed(L("대화 요약을 만들지 못했습니다."), code: "E-MAC-MEM-0001")
    }
    return summary
  }

  /// 요약 본문을 직접 편집한다 — 경계와 자동 정리 상태는 유지한다.
  func updateConversationSummary(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      compactMessage = L("요약을 비워 둘 수 없습니다. 지우려면 [요약 해제]를 누르세요.")
      return
    }
    guard conversation.summary != nil else { return }
    core.replaceSummary(trimmed)
    conversation = core.conversation
    syncArchive()
    compactMessage = nil
    NSLog("[QuickTalk] 대화 요약 직접 편집 — %d자", trimmed.count)
  }

  /// 요약 해제 — 사용자가 명시적으로 해제했으므로 자동 정리를 멈춘다.
  func clearConversationMemory() {
    core.clearSummary(pauseAuto: true)
    conversation = core.conversation
    syncArchive()
    compactMessage = nil
    NSLog("[QuickTalk] 대화 요약 해제 — 자동 정리 일시 중지")
  }

  /// 자동 정리 다시 켜기 — 바로 예산을 넘었으면 백그라운드로 정리한다.
  func resumeAutoCompact() {
    core.resumeAutoCompact()
    conversation = core.conversation
    syncArchive()
    // 답변 중이면 끝난 뒤 다음 턴에서 자동으로 판단한다(반쪽 답변을 요약하지 않음).
    if !isReplying { startAutoCompact(convID: conversation.id) }
  }

  // MARK: - 웹 검색 실행 (PLAN_v0.14)

  /// Exa 키가 저장되어 있는가(키 값 자체는 읽지 않고 존재만 확인)
  var webSearchKeyReady: Bool { SecretStore.has(account: settings.exaSecretID) }

  /// 오늘 보낸 네트워크 검색 횟수(캐시 적중 제외).
  var webSearchUsageToday: Int {
    WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                             count: settings.webSearchUsageCount)
  }

  /// 검색 1회 — 캐시(10분) 우선. 실패는 `WebSearchError`로만 돌려준다(답변은 계속).
  /// Exa 검색 1회 — **메인 액터에서만** 돈다.
  ///
  /// `settings`(사용량 카운터)를 갱신하는데, 이 함수가 비격리 async로 돌면 `await` 뒤
  /// 협력 스레드에서 재개되어 **Published 값을 메인 밖에서 바꾼다**. 그러면 SwiftUI가 그 스레드에서
  /// 뷰를 갱신하고, AppKit 입력창이 창 드래그 영역을 건드리며
  /// `NSWindow drag regions should only be invalidated on the Main Thread!` 예외로 **앱이 죽는다**
  /// (2026-10-21 실사용 크래시: 첨부 있는 질문 수정 → 전송 → SIGABRT).
  @MainActor
  func searchWeb(query: String, useCache: Bool = true) async -> Result<[SearchResult], WebSearchError> {
    let s = settings
    guard s.webSearchProvider == .exa else { return .failure(.missingKey) }
    guard let key = SecretStore.load(account: s.exaSecretID), !key.isEmpty else {
      return .failure(.missingKey)
    }
    // 날짜가 바뀌었으면 카운터를 리셋한다(로컬 시간 기준).
    let today = WebSearchQuota.dayKey()
    if s.webSearchUsageDay != today {
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = 0
    }
    let keyStr = SearchCache.key(provider: s.webSearchProvider, query: query,
                                 freshness: s.webSearchFreshness,
                                 count: s.webSearchResultCount,
                                 maxCharacters: s.webSearchMaxCharacters)
    // 캐시 적중은 네트워크 호출이 아니므로 한도보다 **먼저** 확인한다.
    // (한도 도달 후에도 이미 받은 결과는 쓸 수 있어야 한다.)
    if useCache, let hit = searchCache.get(keyStr) { return .success(hit) }
    let used = WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                                        count: settings.webSearchUsageCount)
    if WebSearchQuota.limitReached(limit: s.webSearchDailyLimit, used: used) {
      NSLog("[QuickTalk] 웹 검색 일일 한도 도달 — %d/%d", used, s.webSearchDailyLimit)
      return .failure(.dailyLimit)
    }
    do {
      let results = try await ExaSearchClient(apiKey: key)
        .search(query: query,
                count: s.webSearchResultCount,
                freshness: s.webSearchFreshness,
                maxCharacters: s.webSearchMaxCharacters)
      if !results.isEmpty { searchCache.put(results, key: keyStr) }
      // HTTP 응답을 받은 검색은 결과 0건이어도 비용이 발생할 수 있으므로 센다.
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = used + 1
      return .success(results)
    } catch let error as WebSearchError {
      return .failure(error)
    } catch {
      return .failure(.network(AIErrorText.shortDetail(for: error)))
    }
  }

  /// Exa `/answer` 1회 — 검색+요약+인용을 한 번에. 실패는 `WebSearchError`로 돌려준다.
  /// 일반 검색과 같은 일일 한도를 공유한다(네트워크 호출 1회 = 카운트 1).
  /// 같은 질문은 10분 캐시를 먼저 확인한다(한도·지연 절약).
  /// `searchWeb`과 같은 이유로 **메인 액터 고정**(설정 카운터를 안전하게 갱신).
  @MainActor
  func answerWeb(query: String, useCache: Bool = true) async -> Result<ExaAnswerResult, WebSearchError> {
    let s = settings
    guard s.webSearchProvider == .exa else { return .failure(.missingKey) }
    guard let key = SecretStore.load(account: s.exaSecretID), !key.isEmpty else {
      return .failure(.missingKey)
    }
    let today = WebSearchQuota.dayKey()
    if s.webSearchUsageDay != today {
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = 0
    }
    let keyStr = ExaAnswerCache.key(query: query)
    if useCache, let hit = answerCache.get(keyStr) { return .success(hit) }
    let used = WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                                        count: settings.webSearchUsageCount)
    if WebSearchQuota.limitReached(limit: s.webSearchDailyLimit, used: used) {
      return .failure(.dailyLimit)
    }
    do {
      let result = try await ExaAnswerClient(apiKey: key).answer(query: query)
      answerCache.put(result, for: keyStr)
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = used + 1
      return .success(result)
    } catch let error as WebSearchError {
      return .failure(error)
    } catch {
      return .failure(.network(AIErrorText.shortDetail(for: error)))
    }
  }

  /// 툴 콜링 1왕복 — 모델이 `web_search`를 호출하면 검색을 실행해 결과를 돌려준다.
  /// 호출이 없으면 모델이 바로 답한 것으로 보고 그 본문을 쓴다.
  enum WebToolPlan {
    case search([SearchResult])
    case answer(String)
    /// tools 미지원(4xx) — 기존 주입 경로로 폴백한다.
    case unsupported(String)
    /// 네트워크·인증·5xx — 두 번째 모델 호출을 하지 않고 검색 없이 답한다.
    case failed(String)
  }

  func planWebToolCall(provider: LLMProviderConfig,
                               prompt: String,
                               history: [Turn],
                               attachments: [OutgoingAttachment]) async -> WebToolPlan {
    guard provider.type == .openAICompatible, !provider.model.isEmpty else {
      return .unsupported(L("⚠️ 툴 콜링은 OpenAI 호환 프로바이더에서만 동작합니다."))
    }
    // 검색 키가 없으면 모델을 한 번 더 부르지 않는다(호출 후 빈 결과가 되는 것 방지).
    guard settings.webSearchEnabled, webSearchKeyReady else {
      return .failed(L("⚠️ Exa 키가 없어 웹 검색을 건너뜁니다."))
    }
    guard !provider.secretID.isEmpty,
          let key = SecretStore.load(account: provider.secretID), !key.isEmpty else {
      return .failed(L("⚠️ API 키가 없어 툴 콜링을 건너뜁니다."))
    }
    guard let base = URL(string: provider.baseURL) else {
      return .failed(L("⚠️ 주소가 올바르지 않아 툴 콜링을 건너뜁니다."))
    }
    let client = OpenAIClient(baseURL: base, apiKey: key, model: provider.model)
    let messages = OpenAIClient.buildMessages(prompt: prompt, history: history,
                                              attachments: attachments)
    do {
      let response = try await client.completion(messages: messages,
                                                 tools: WebSearchTool.schema)
      let calls = response.calls
        .filter { $0.name == WebSearchTool.name && $0.query != nil }
        .prefix(WebSearchTool.maxCallsPerTurn)
      if calls.isEmpty {
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .search([]) : .answer(text)
      }
      var results: [SearchResult] = []
      var seenURLs = Set<String>()
      var seenQueries = Set<String>()
      for call in calls {
        guard let query = call.query else { continue }
        // 같은 검색어를 여러 번 호출한 모델도 네트워크/쿼터를 중복 사용하지 않는다.
        let queryKey = query.lowercased()
          .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard seenQueries.insert(queryKey).inserted else { continue }
        let outcome = await searchWeb(query: query)
        guard case .success(let found) = outcome else { continue }
        for r in found where seenURLs.insert(r.url.lowercased()).inserted {
          results.append(r)
        }
      }
      return .search(Array(results.prefix(max(1, settings.webSearchResultCount))))
    } catch {
      if error is WebToolError || WebToolError.isToolUnsupported(error) {
        // tools 미지원(400/404/422) 또는 해석 불가 응답 — 기존 주입 방식으로 폴백한다.
        return .unsupported(L("⚠️ 툴 콜링을 사용할 수 없어 검색 결과 주입으로 전환했습니다."))
      }
      // 인증·한도·5xx·네트워크 — 폴백해도 같은 실패가 반복되므로 검색 없이 답한다.
      return .failed(Lf("⚠️ 툴 콜링 요청이 실패해 검색 없이 답합니다 (%@)",
                        AIErrorText.code(for: error)))
    }
  }

  /// QA 헤드리스 — 툴 콜링 1왕복. 결과 건수/답변 여부만 돌려준다(질문·본문 로그 금지).
  func toolCallingSelfTest(query: String) async -> String {
    guard let provider = settings.activeProvider else { return "FAIL no-provider" }
    let plan = await planWebToolCall(provider: provider, prompt: query,
                                     history: [], attachments: [])
    switch plan {
    case .search(let results): return "OK search results=\(results.count)"
    case .answer(let text): return "OK answer chars=\(text.count)"
    case .unsupported: return "FALLBACK unsupported"
    case .failed(let detail): return "FAIL \(detail)"
    }
  }

  /// 설정 › AI의 [답변 API 테스트] — 본문·키·검색어는 로그에 남기지 않는다.
  func testExaAnswer() {
    guard !answerTesting else { return }
    answerTesting = true
    answerTestResult = ""
    Task { @MainActor in
      let started = Date()
      let outcome = await self.answerWeb(query: "오늘 뉴스", useCache: false)
      self.answerTesting = false
      switch outcome {
      case .success(let result):
        let secs = Date().timeIntervalSince(started)
        self.answerTestResult = Lf("답변 %d자 · 인용 %d건 · %.1f초",
                                   result.answer.count, result.sources.count, secs)
      case .failure(let error):
        self.answerTestResult = error.userText
      }
    }
  }

  /// "필요할 때만" 자동 판정 — 활성 모델에게 **검색 필요 여부만** 짧게 묻는다.
  /// 질문 문구의 키워드 목록으로 추측하지 않는다(사용자가 든 예시가 규칙이 되지 않게).
  /// 실패·시간 초과면 검색하지 않는다 — 답변 지연·비용을 늘리지 않는 쪽을 택한다.
  func decidesToSearch(_ prompt: String, history: [Turn] = []) async -> Bool {
    guard let provider = settings.activeProvider else { return false }
    let previous = history.last(where: { $0.role == .user })?.text
    let key = Self.searchDecisionKey(providerID: provider.id,
                                     previous: previous,
                                     prompt: prompt)
    if let hit = searchDecisionCache[key],
       Date().timeIntervalSince(hit.at) < searchDecisionTTL {
      NSLog("[QuickTalk] 검색 필요 판정 캐시 %@", hit.needed ? "YES" : "NO")
      return hit.needed
    }
    let question = WebSearchQuery.classifierPrompt(question: prompt,
                                                   previousQuestion: previous)
    let started = Date()
    // 타임아웃은 프로바이더별 — 온디바이스 5초, 원격 8초, Ollama 20초(콜드 로드까지, Core 주석 참조)
    let timeout = WebSearchQuery.classifierTimeout(for: provider.type)
    // 일시 오류(429·5xx·네트워크)는 **1회 재시도**한다. 빨리 실패하므로 추가 지연이 작고,
    // 실패를 곧 "검색 안 함"으로 굳히면 최신 정보가 필요한 질문이 조용히 검색 없이 답해진다.
    // 시간 초과는 이미 오래 기다린 것이라 재시도하지 않는다.
    var attempt = 1
    while true {
      do {
        let answer = try await Self.classifierAnswer(provider: provider, prompt: question,
                                                     timeout: timeout)
        let needed = WebSearchQuery.parseNeed(answer)
        rememberSearchDecision(needed, key: key)
        NSLog("[QuickTalk] 검색 필요 판정 %@ (%dms, 시도 %d)", needed ? "YES" : "NO",
              Int(Date().timeIntervalSince(started) * 1000), attempt)
        return needed
      } catch {
        // 원인을 구분해 남긴다 — 시간 초과(E-MAC-SEARCH-0004)와 프로바이더 오류(네트워크·인증·5xx)는 대응이 다르다
        let code = AIErrorText.code(for: error)
        if attempt < 2, WebSearchQuery.classifierRetryAllowed(after: code) {
          NSLog("[QuickTalk] 검색 필요 판정 일시 오류(%@) → 1회 재시도 (%dms)",
                code, Int(Date().timeIntervalSince(started) * 1000))
          // 429 직후 즉시 재시도하면 같은 제한에 걸리기 쉬워 아주 짧게 쉰다.
          try? await Task.sleep(nanoseconds: 400_000_000)
          attempt += 1
          continue
        }
        NSLog("[QuickTalk] 검색 필요 판정 실패 → 검색 안 함 (제한 %.0f초, %dms, code=%@, 시도 %d)",
              timeout, Int(Date().timeIntervalSince(started) * 1000), code, attempt)
        return false
      }
    }
  }

  /// 판정 캐시 키 — 모델·직전 질문·현재 질문. 대소문자/공백만 정규화한다.
  static func searchDecisionKey(providerID: String, previous: String?, prompt: String) -> String {
    let norm: (String) -> String = { s in
      s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    return "\(providerID)|\(norm(previous ?? ""))|\(norm(prompt))"
  }

  private func rememberSearchDecision(_ needed: Bool, key: String) {
    if searchDecisionCache.count >= 50 { searchDecisionCache.removeAll() }
    searchDecisionCache[key] = (needed, Date())
  }

  /// 분류용 짧은 호출 — `timeout`초를 넘기면 취소하고 nil(검색 안 함)로 처리한다.
  private static func classifierAnswer(provider: LLMProviderConfig,
                                       prompt: String,
                                       timeout: TimeInterval) async throws -> String {
    try await withThrowingTaskGroup(of: String?.self) { group in
      group.addTask {
        try await UIStore.reply(provider: provider, prompt: prompt, history: [])
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        return nil
      }
      let first = try await group.next() ?? nil
      group.cancelAll()
      guard let answer = first else {
        throw QuickTalkError.detailed(L("검색 필요 여부 판정 시간 초과"),
                                      code: "E-MAC-SEARCH-0004")
      }
      return answer
    }
  }

  /// 설정 › AI의 [검색 테스트] — 건수·지연만 표시한다(본문·키·검색어 로그 금지).
  func testWebSearch() {
    guard !webSearchTesting else { return }
    webSearchTesting = true
    webSearchTestResult = ""
    Task { @MainActor in
      let started = Date()
      let outcome = await self.searchWeb(query: "오늘 뉴스", useCache: false)
      self.webSearchTesting = false
      switch outcome {
      case .success(let results):
        let secs = Date().timeIntervalSince(started)
        self.webSearchTestResult = results.isEmpty
          ? L("응답은 왔지만 결과가 0건입니다.")
          : Lf("검색 %d건 · %.1f초", results.count, secs)
      case .failure(let error):
        self.webSearchTestResult = error.userText
      }
    }
  }

  /// 검색 캐시 비우기 — 같은 질문을 다시 검색하고 싶을 때
  func clearWebSearchCache() {
    searchCache.clear()
    answerCache.clear()
    webSearchTestResult = L("검색·답변 캐시를 비웠습니다.")
  }

  /// 전송 직후 같은 텍스트가 다시 들어오면(IME 조합 커밋 에코) 무시하고 입력창을 비운다.
  /// 사용자가 곧바로 다른 내용을 입력하기 시작하면 즉시 중단한다.
  private func suppressEcho(of text: String) {
    guard !text.isEmpty else { return }
    Task { @MainActor in
      for _ in 0..<25 {                       // 약 0.5초
        try? await Task.sleep(nanoseconds: 20_000_000)
        if draft == text { draft = "" }
        else if !draft.isEmpty { return }      // 새 입력이 들어오면 중단
      }
    }
  }

  /// 폴백 안내 한 줄 — 화면·데모 렌더가 **같은 문구**를 쓰도록 한 곳에 둔다.
  static func fallbackNote(primaryName: String, fallbackName: String, error: Error) -> String {
    Lf("⚠️ 주 모델(%@)이 응답하지 않아 예비 모델(%@)로 답했습니다 — %@\n\n",
       primaryName, fallbackName, ProviderFallback.reason(for: error))
  }

  /// 주 모델 → (일시 오류면) **예비 모델 1회**. 이미 글자가 화면에 나간 뒤에는 전환하지 않는다.
  /// 예비 모델의 첫 글자가 올 때 안내를 붙인다 — 예비도 실패하면 안내만 남지 않게.
  @MainActor
  static func streamReplyWithFallback(settings: QuickTalkSettings,
                                      provider primary: LLMProviderConfig,
                                      prompt: String,
                                      history: [Turn],
                                      attachments: [OutgoingAttachment],
                                      onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    do {
      return try await streamReply(provider: primary, prompt: prompt, history: history,
                                   attachments: attachments, onDelta: onDelta)
    } catch {
      let primaryError = error
      let primaryCode = AIErrorText.code(for: primaryError)
      guard let fb = settings.fallbackProvider,
            ProviderFallback.isUsable(fb, keyExists: { SecretStore.has(account: $0) }),
            ProviderFallback.allowed(after: primaryError) else { throw primaryError }
      NSLog("[WARN] E-MAC-FALLBACK-0001 주 모델 실패(%@) → 예비 모델 1회 시도", primaryCode)
      let note = fallbackNote(primaryName: primary.displayName,
                              fallbackName: fb.displayName,
                              error: primaryError)
      // 예비 모델은 예산이 더 작을 수 있다(원격 → Apple FM). 그 예산에 맞춰 오래된 턴을 덜어낸다.
      let fitted = Conversation(turns: history)
      let fallbackHistory = ConversationMemory.fitHistory(fitted, prompt: prompt,
                                                          provider: fb).history
      // 첫 델타에서 안내를 내보내기 위한 플래그(동시성 경고 없이 값 전달).
      final class Announced { var value = false }
      let announced = Announced()
      do {
        let text = try await streamReply(
          provider: fb, prompt: prompt, history: fallbackHistory, attachments: attachments,
          onDelta: { delta in
            if !announced.value {
              announced.value = true
              onDelta(note)
            }
            onDelta(delta)
          })
        // 델타를 한 번도 내보내지 않는 클라이언트도 안내를 잃지 않게 반환값에도 붙인다
        // (스트리밍 경로에서는 화면 텍스트와 같은 값이 된다).
        return note + text
      } catch let fallbackError {
        NSLog("[ERROR] E-MAC-FALLBACK-0002 예비 모델도 실패 — %@",
              AIErrorText.logLabel(for: fallbackError))
        throw QuickTalkError.detailed(
          Lf("주 모델(%@) 실패(%@) 후 예비 모델(%@)도 실패했습니다 — %@",
             primary.displayName, primaryCode, fb.displayName,
             ProviderFallback.reason(for: fallbackError)),
          code: AIErrorText.code(for: fallbackError))
      }
    }
  }

  /// 스트리밍 응답 — 활성 AI·모델 1건. 델타는 메인 액터에서 **도착 순서대로** 온다.
  /// OpenAI 호환=SSE, Ollama=NDJSON, Apple FM=한 번에(FoundationModels 스트리밍 미사용).
  @MainActor
  static func streamReply(provider p: LLMProviderConfig, prompt: String, history: [Turn],
                          attachments: [OutgoingAttachment],
                          onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    switch p.type {
    case .appleFM:
      let skipped = attachments.filter { $0.hasImage }
      let answer = try await appleFMReply(prompt: prompt, history: history, attachments: attachments)
      if !skipped.isEmpty {
        onDelta(Lf("⚠️ Apple FM은 이미지를 받지 못해 %d건을 빼고 보냈습니다.\n\n", skipped.count))
      }
      onDelta(answer)
      return answer
    case .ollama:
      guard !p.model.isEmpty else {
        throw QuickTalkError.detailed(L("모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요."),
                                      code: "E-MAC-NET-0002")
      }
      guard let host = URL(string: p.baseURL) else {
        throw QuickTalkError.detailed(Lf("호스트 주소가 올바르지 않습니다: %@", p.baseURL),
                                      code: "E-MAC-NET-0002")
      }
      return try await AttachmentRetry.stream(client: OllamaClient(host: host, model: p.model),
                                              prompt: prompt, history: history,
                                              attachments: attachments, model: p.model,
                                              onDelta: onDelta)
    case .openAICompatible:
      guard !p.model.isEmpty else {
        throw QuickTalkError.detailed(L("모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요."),
                                      code: "E-MAC-NET-0002")
      }
      guard !p.secretID.isEmpty,
            let key = SecretStore.load(account: p.secretID), !key.isEmpty else {
        throw QuickTalkError.detailed(L("API 키가 없습니다. 설정 > AI에서 키를 저장해 주세요."),
                                      code: "E-MAC-KEY-0001")
      }
      guard let base = URL(string: p.baseURL) else {
        throw QuickTalkError.detailed(Lf("주소가 올바르지 않습니다: %@", p.baseURL),
                                      code: "E-MAC-NET-0002")
      }
      return try await AttachmentRetry.stream(client: OpenAIClient(baseURL: base, apiKey: key, model: p.model),
                                              prompt: prompt, history: history,
                                              attachments: attachments, model: p.model,
                                              onDelta: onDelta)
    }
  }

  /// 첨부 파일 본문 읽기 — 무거운 작업(파일 IO·이미지 base64)은 메인 밖에서 한다.
  nonisolated static func loadAttachments(_ pending: [PendingAttachment]) async -> [OutgoingAttachment] {
    guard !pending.isEmpty else { return [] }
    let items = pending.map { (name: $0.name, kind: $0.kind, url: $0.url) }
    return await Task.detached(priority: .userInitiated) {
      items.map { AttachmentLoader.load(name: $0.name, kind: $0.kind, url: $0.url) }
    }.value
  }

  /// 키가 필요 없는 프로바이더 ID — 원격 키 미저장 시 폴백 대상
  private static func keylessFallbackID(in s: QuickTalkSettings) -> String? {
    if let fm = s.providers.first(where: { $0.id == LLMProviderConfig.appleFMID && $0.enabled }) {
      return fm.id
    }
    return s.providers.first { $0.enabled && $0.type != .openAICompatible }?.id
      ?? s.providers.first { $0.enabled }?.id
  }

  /// 프로바이더 1건으로 응답 수신 (설정 UI의 "테스트" 버튼에서도 재사용).
  /// 실패는 목업으로 숨기지 않고 에러코드 문구로 반환한다.
  static func reply(provider p: LLMProviderConfig,
                    prompt: String,
                    history: [Turn],
                    attachments: [OutgoingAttachment] = []) async throws -> String {
    let answer = try await replyRaw(provider: p, prompt: prompt, history: history, attachments: attachments)
    // 줄여 보냄·잘라냄·미전송 사유는 숨기지 않고 답변 앞에 붙인다(무음 실패 금지)
    return AttachmentLoader.warnings(attachments) + answer
  }

  /// 첨부 전송 — 실패 분류별 재시도 사다리는 Core(`AttachmentRetry`)에 있다(P2).
  private static func sendWithAttachmentFallback(client: any LLMClient,
                                                 prompt: String,
                                                 history: [Turn],
                                                 attachments: [OutgoingAttachment],
                                                 model: String) async throws -> String {
    try await AttachmentRetry.send(client: client, prompt: prompt, history: history,
                                   attachments: attachments, model: model)
  }

  private static func replyRaw(provider p: LLMProviderConfig,
                               prompt: String,
                               history: [Turn],
                               attachments: [OutgoingAttachment]) async throws -> String {
    switch p.type {
    case .appleFM:
      let skipped = attachments.filter { $0.hasImage }
      let answer = try await appleFMReply(prompt: prompt, history: history, attachments: attachments)
      return skipped.isEmpty ? answer
        : Lf("⚠️ Apple FM은 이미지를 받지 못해 %d건을 빼고 보냈습니다.\n\n", skipped.count) + answer
    case .ollama:
      guard !p.model.isEmpty else {
        return L("(오류 E-MAC-NET-0002) 모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요.")
      }
      guard let host = URL(string: p.baseURL) else {
        return Lf("(오류 E-MAC-NET-0002) 호스트 주소가 올바르지 않습니다: %@", p.baseURL)
      }
      // 연결 거부·시간 초과·서버 오류를 그대로 전달한다 — UI가 `AIErrorText`로 정확한 원인을 만든다
      return try await sendWithAttachmentFallback(client: OllamaClient(host: host, model: p.model),
                                                 prompt: prompt, history: history,
                                                 attachments: attachments, model: p.model)
    case .openAICompatible:
      guard !p.model.isEmpty else {
        return L("(오류 E-MAC-NET-0002) 모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요.")
      }
      guard !p.secretID.isEmpty,
            let key = SecretStore.load(account: p.secretID), !key.isEmpty else {
        return L("(오류 E-MAC-KEY-0001) API 키가 없습니다. 설정 > AI에서 키를 저장해 주세요.")
      }
      guard let base = URL(string: p.baseURL) else {
        return Lf("(오류 E-MAC-NET-0002) 주소가 올바르지 않습니다: %@", p.baseURL)
      }
      return try await sendWithAttachmentFallback(client: OpenAIClient(baseURL: base, apiKey: key, model: p.model),
                                                 prompt: prompt, history: history,
                                                 attachments: attachments, model: p.model)
    }
  }
}
