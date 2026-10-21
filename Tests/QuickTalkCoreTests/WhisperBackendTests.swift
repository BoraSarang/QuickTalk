import XCTest
@testable import QuickTalkCore

/// Whisper 두 백엔드(mlx-whisper · whisper.cpp) 지원 검증
final class WhisperBackendTests: XCTestCase {

  /// /var ↔ /private/var 심볼릭 링크 차이 제거(임시 폴더 경로 비교용)
  private func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }

  // MARK: - 실행 인자

  func testWhisperCppArguments() {
    let args = WhisperService.arguments(for: .whisperCpp, model: "/m/ggml-large.bin",
                                        language: "ko", wavPath: "/tmp/a.wav", outputDir: "/tmp/out")
    XCTAssertEqual(args, ["-m", "/m/ggml-large.bin", "-f", "/tmp/a.wav", "-nt", "-np", "-l", "ko"])
    // 언어 자동(빈 값)이면 -l 을 넣지 않는다
    let auto = WhisperService.arguments(for: .whisperCpp, model: "/m/x.bin",
                                        language: "", wavPath: "/tmp/a.wav", outputDir: "/tmp/out")
    XCTAssertFalse(auto.contains("-l"))
  }

  func testMLXArguments() {
    let args = WhisperService.arguments(for: .mlxWhisper, model: "/m/mlx-model",
                                        language: "ko", wavPath: "/tmp/a.wav", outputDir: "/tmp/out")
    XCTAssertEqual(args.first, "--model")
    XCTAssertTrue(args.contains("/m/mlx-model"))
    XCTAssertTrue(args.contains("--output-format"))
    XCTAssertTrue(args.contains("txt"))
    XCTAssertTrue(args.contains("--output-dir"))
    XCTAssertTrue(args.contains("/tmp/out"))
    XCTAssertEqual(args.last, "/tmp/a.wav", "오디오 경로는 맨 뒤 위치 인자")
    XCTAssertTrue(args.contains("--language"))
    let auto = WhisperService.arguments(for: .mlxWhisper, model: "/m/mlx-model",
                                        language: "", wavPath: "/tmp/a.wav", outputDir: "/tmp/out")
    XCTAssertFalse(auto.contains("--language"))
  }

  func testMLXTranscriptParsing() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-whisper-out-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let wav = dir.appendingPathComponent("quicktalk-voice.wav")
    try "안녕하세요. 테스트입니다.\n".write(to: dir.appendingPathComponent("quicktalk-voice.txt"),
                                        atomically: true, encoding: .utf8)
    XCTAssertEqual(WhisperService.readMLXTranscript(outputDir: dir, wav: wav),
                   "안녕하세요. 테스트입니다.")
    XCTAssertNil(WhisperService.readMLXTranscript(outputDir: dir,
                                                  wav: dir.appendingPathComponent("없음.wav")))
  }

  // MARK: - 모델 탐색

  func testDetectModelsFindsGGMLAndMLXOnly() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-whisper-\(UUID().uuidString)")
    let mlx = root.appendingPathComponent("mlx-whisper-test-model")
    try FileManager.default.createDirectory(at: mlx, withIntermediateDirectories: true)
    try "{}".write(to: mlx.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    try Data(repeating: 1, count: 4096).write(to: mlx.appendingPathComponent("weights.safetensors"))
    try Data(repeating: 2, count: 2048).write(to: root.appendingPathComponent("ggml-test.bin"))
    // 모델이 아닌 것들 — 잡히면 안 된다
    let junk = root.appendingPathComponent("그냥폴더")
    try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
    try "메모".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    var settings = QuickTalkSettings()
    settings.whisperModelFolder = root.path
    let mine = WhisperService.detectModels(settings: settings)
      .filter { resolved($0.path).hasPrefix(resolved(root.path)) }

    XCTAssertEqual(mine.count, 2)
    XCTAssertEqual(mine.first(where: { $0.kind == .ggml })?.name, "ggml-test.bin")
    XCTAssertEqual(mine.first(where: { $0.kind == .mlx })?.name, "mlx-whisper-test-model")
    XCTAssertFalse(mine.contains { $0.name == "그냥폴더" })
    XCTAssertFalse(mine.contains { $0.name == "readme.txt" })

    let onlyGGML = WhisperService.detectModels(settings: settings, kind: .ggml)
      .filter { resolved($0.path).hasPrefix(resolved(root.path)) }
    XCTAssertEqual(onlyGGML.count, 1)
    XCTAssertEqual(onlyGGML.first?.kind, .ggml)
  }

  func testDetectModelsPrefersBiggerModelInSameFolder() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-whisper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 1024).write(to: root.appendingPathComponent("ggml-aaa-small.bin"))
    try Data(repeating: 2, count: 8192).write(to: root.appendingPathComponent("ggml-zzz-big.bin"))
    defer { try? FileManager.default.removeItem(at: root) }

    var settings = QuickTalkSettings()
    settings.whisperModelFolder = root.path
    let mine = WhisperService.detectModels(settings: settings, kind: .ggml)
      .filter { resolved($0.path).hasPrefix(resolved(root.path)) }
    XCTAssertEqual(mine.first?.name, "ggml-zzz-big.bin", "큰 모델이 자동 선택 1순위")
    XCTAssertEqual(resolved(WhisperService.modelPath(for: .whisperCpp, settings: settings)),
                   resolved(root.appendingPathComponent("ggml-zzz-big.bin").path),
                   "자동 선택은 큰 모델")
  }

  func testModelPathUsesExplicitThenDetected() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-whisper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // 이름이 앞서므로 자동 선택은 이 파일이 된다
    let ggml = root.appendingPathComponent("ggml-aaa-test.bin")
    try Data(repeating: 3, count: 1024).write(to: ggml)
    defer { try? FileManager.default.removeItem(at: root) }

    var settings = QuickTalkSettings()
    settings.whisperModelFolder = root.path
    XCTAssertEqual(resolved(WhisperService.modelPath(for: .whisperCpp, settings: settings)),
                   resolved(ggml.path),
                   "설정이 비어 있으면 검색 폴더에서 감지한 모델을 쓴다")

    settings.whisperModelPath = "/직접/지정.bin"
    XCTAssertEqual(WhisperService.modelPath(for: .whisperCpp, settings: settings), "/직접/지정.bin",
                   "직접 지정이 감지보다 우선한다")
  }

  func testSearchFoldersSkipsMissingAndDedups() {
    var settings = QuickTalkSettings()
    settings.whisperModelFolder = "/존재하지/않는/폴더"
    let folders = WhisperService.searchFolders(settings: settings).map(\.path)
    XCTAssertFalse(folders.contains("/존재하지/않는/폴더"))
    XCTAssertEqual(folders.count, Set(folders).count)
  }

  // MARK: - 백엔드 확정

  func testResolvedBackendHonoursExplicitChoice() {
    var settings = QuickTalkSettings()
    settings.whisperBackend = .whisperCpp
    XCTAssertEqual(WhisperService.resolvedBackend(settings: settings), .whisperCpp)
    settings.whisperBackend = .mlxWhisper
    XCTAssertEqual(WhisperService.resolvedBackend(settings: settings), .mlxWhisper)
    // 자동은 설치된 것 중 하나로 해석된다(둘 다 없으면 whisper.cpp 안내로)
    settings.whisperBackend = .auto
    XCTAssertTrue([.mlxWhisper, .whisperCpp].contains(WhisperService.resolvedBackend(settings: settings)))
  }

  func testBackendModelKinds() {
    XCTAssertEqual(WhisperBackend.whisperCpp.modelKind, .ggml)
    XCTAssertEqual(WhisperBackend.mlxWhisper.modelKind, .mlx)
    XCTAssertNil(WhisperBackend.auto.modelKind)
  }

  func testLanguageOptionsIncludeAutoAndKorean() {
    let values = WhisperService.languageOptions.map(\.0)
    XCTAssertTrue(values.contains(""))
    XCTAssertTrue(values.contains("ko"))
  }

  func testSettingsRoundTripKeepsWhisperFields() throws {
    var s = QuickTalkSettings()
    s.whisperBackend = .mlxWhisper
    s.whisperMLXModelPath = "/m/mlx"
    s.whisperModelPath = "/m/ggml.bin"
    s.whisperLanguage = "ja"
    s.whisperModelFolder = "/m"
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.whisperBackend, .mlxWhisper)
    XCTAssertEqual(back.whisperMLXModelPath, "/m/mlx")
    XCTAssertEqual(back.whisperModelPath, "/m/ggml.bin")
    XCTAssertEqual(back.whisperLanguage, "ja")
    XCTAssertEqual(back.whisperModelFolder, "/m")
  }

  func testLegacySettingsDecodeDefaultsToAutoKorean() throws {
    // 예전 설정 파일(whisper 키 없음) → 자동 · 한국어로 승계
    let old = #"{"showMenuBarIcon":true,"voiceEngine":"Whisper 로컬"}"#
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: Data(old.utf8))
    XCTAssertEqual(decoded.whisperBackend, .auto)
    XCTAssertEqual(decoded.whisperLanguage, "ko")
  }

  func testProcessEnvironmentAugmentsPath() {
    let env = WhisperService.processEnvironment()
    let path = env["PATH"] ?? ""
    XCTAssertTrue(path.contains("/opt/homebrew/bin"))
    XCTAssertLessThan(path.range(of: "/opt/homebrew/bin")!.lowerBound,
                      path.range(of: "/usr/bin")?.lowerBound ?? path.endIndex,
                      "Homebrew 경로가 시스템 경로보다 앞에 온다")
    XCTAssertEqual(path.split(separator: ":").count, Set(path.split(separator: ":")).count,
                   "PATH 중복 없음")
  }
}

// MARK: - 살아있는 전사 검증(두 백엔드 모두)
// `QT_LIVE_WHISPER=/path/to.wav swift test --filter LiveWhisperCheck`
final class LiveWhisperCheck: XCTestCase {

  func testBothBackendsTranscribe() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let wav = env["QT_LIVE_WHISPER"], FileManager.default.fileExists(atPath: wav) else {
      throw XCTSkip("QT_LIVE_WHISPER=<wav 경로> 일 때만 실행")
    }

    var settings = QuickTalkSettings()
    settings.whisperLanguage = env["QT_LIVE_LANG"] ?? "ko"

    // 이 Mac에 실제로 있는 모델 목록
    let models = WhisperService.detectModels(settings: settings)
    print("[LIVE] 감지된 모델: " + models.map { "\($0.kind.rawValue):\($0.name)(\($0.sizeText))" }.joined(separator: ", "))

    for backend in [WhisperBackend.mlxWhisper, .whisperCpp] {
      settings.whisperBackend = backend
      guard WhisperService.isReady(backend: backend, settings: settings) else {
        print("[LIVE] \(backend.shortName) 준비 안 됨 — \(WhisperService.statusLine(for: backend, settings: settings))")
        continue
      }
      let model = WhisperService.modelPath(for: backend, settings: settings)
      let started = Date()
      let text = try await WhisperService.transcribe(wavURL: URL(fileURLWithPath: wav), settings: settings)
      print("[LIVE] \(backend.shortName) [\(URL(fileURLWithPath: model).lastPathComponent)] "
            + String(format: "%.1f초 → ", Date().timeIntervalSince(started)) + text)
      XCTAssertFalse(text.isEmpty, "\(backend.shortName) 결과가 비었다")
    }
  }
}
