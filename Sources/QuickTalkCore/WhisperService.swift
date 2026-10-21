import Foundation

// Whisper 로컬 전사 — **두 백엔드를 모두 지원**한다 (PLAN_v0.13+).
//  · whisper.cpp  : `whisper-cli` + ggml-*.bin (CPU, 가볍다)
//  · mlx-whisper  : `mlx_whisper` + MLX 모델 폴더 (Apple GPU, 정확도 높음)
// 바이너리·모델이 없으면 상태 문구로 안내한다 (무음 실패 금지).

/// Whisper 전사 백엔드
public enum WhisperBackend: String, Codable, CaseIterable, Identifiable {
  case auto
  case mlxWhisper
  case whisperCpp

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .auto: return L("자동 (설치된 것 우선)")
    case .mlxWhisper: return "mlx-whisper (Apple GPU)"
    case .whisperCpp: return "whisper.cpp (CPU)"
    }
  }

  public var shortName: String {
    switch self {
    case .auto: return L("자동")
    case .mlxWhisper: return "mlx-whisper"
    case .whisperCpp: return "whisper.cpp"
    }
  }

  /// 이 백엔드가 쓰는 모델 형식
  public var modelKind: WhisperModel.Kind? {
    switch self {
    case .whisperCpp: return .ggml
    case .mlxWhisper: return .mlx
    case .auto: return nil
    }
  }

  public var installHint: String {
    switch self {
    case .mlxWhisper: return L("`pip install mlx-whisper`(또는 ~/.venvs/mlx-whisper/bin)")
    case .whisperCpp, .auto: return "`brew install whisper-cpp`"
    }
  }
}

/// 검색 폴더에서 찾은 Whisper 모델 1건
public struct WhisperModel: Identifiable, Equatable {
  public enum Kind: String, Equatable {
    case ggml     // whisper.cpp — ggml-*.bin 파일
    case mlx      // mlx-whisper — config.json + 가중치 폴더
  }

  public var path: String
  public var name: String
  public var kind: Kind
  public var sizeBytes: Int64

  public var id: String { path }

  public var sizeText: String {
    ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
  }

  public init(path: String, name: String, kind: Kind, sizeBytes: Int64) {
    self.path = path; self.name = name; self.kind = kind; self.sizeBytes = sizeBytes
  }
}

public enum WhisperService {

  // MARK: - 바이너리 탐색

  static var home: String { NSHomeDirectory() }

  /// 백엔드별 실행 파일 후보(절대 경로) — venv·Homebrew·수동 설치를 모두 본다
  public static func candidateBinaries(for backend: WhisperBackend) -> [String] {
    let h = home
    switch backend {
    case .mlxWhisper:
      return ["\(h)/.venvs/mlx-whisper/bin/mlx_whisper",
              "/opt/homebrew/bin/mlx_whisper", "/usr/local/bin/mlx_whisper",
              "\(h)/.local/bin/mlx_whisper", "\(h)/.venvs/mlx-whisper/bin/mlx-whisper"]
    case .whisperCpp, .auto:
      return ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli",
              "/opt/homebrew/bin/whisper-cpp", "/usr/local/bin/whisper-cpp",
              "/opt/homebrew/bin/whisper", "/usr/local/bin/whisper"]
    }
  }

  /// PATH 탐색용 이름(앱이 Finder로 뜨면 PATH가 최소라 절대 경로가 우선이다)
  static func searchNames(for backend: WhisperBackend) -> [String] {
    backend == .mlxWhisper ? ["mlx_whisper", "mlx-whisper"] : ["whisper-cli", "whisper-cpp", "whisper"]
  }

  public static func binaryPath(for backend: WhisperBackend) -> String? {
    for p in candidateBinaries(for: backend) where FileManager.default.isExecutableFile(atPath: p) {
      return p
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.environment = processEnvironment()
    for name in searchNames(for: backend) {
      proc.arguments = ["which", name]
      let pipe = Pipe()
      proc.standardOutput = pipe
      proc.standardError = Pipe()
      do { try proc.run() } catch { continue }
      let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      proc.waitUntilExit()
      if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
    }
    return nil
  }

  // MARK: - 모델 탐색

  /// 모델 폴더 기본 위치(사용자가 폴더를 지정하지 않았을 때)
  public static var defaultModelFolders: [URL] {
    [URL(fileURLWithPath: home).appendingPathComponent("Documents/Files/whisper"),
     URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/QuickTalk/models")]
  }

  /// 실제로 뒤져 볼 폴더 목록(지정 폴더 → 기본 위치, 존재하는 것만·중복 제거)
  public static func searchFolders(settings: QuickTalkSettings) -> [URL] {
    var list: [URL] = []
    if !settings.whisperModelFolder.isEmpty {
      list.append(URL(fileURLWithPath: (settings.whisperModelFolder as NSString).expandingTildeInPath))
    }
    list.append(contentsOf: defaultModelFolders)
    var seen = Set<String>()
    var isDir: ObjCBool = false
    return list.filter { url in
      guard seen.insert(url.path).inserted else { return false }
      return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
  }

  /// 폴더에서 모델을 찾는다. 중첩은 1단계까지.
  /// 순서 규칙: **폴더 우선순위**(지정 폴더 → 기본 위치) → 같은 폴더 안에서는 **큰 모델 먼저**
  /// (품질이 좋은 모델이 자동 선택의 첫 후보가 된다 — 예: large-v3-turbo > base)
  public static func detectModels(settings: QuickTalkSettings, kind: WhisperModel.Kind? = nil) -> [WhisperModel] {
    var found: [WhisperModel] = []
    let fm = FileManager.default
    for folder in searchFolders(settings: settings) {
      var inFolder: [WhisperModel] = []
      // 폴더 자체가 MLX 모델일 수 있다
      if let m = mlxModel(at: folder), kind == nil || kind == .mlx { inFolder.append(m) }
      let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
      for entry in entries {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
          if let m = mlxModel(at: entry), kind == nil || kind == .mlx { inFolder.append(m) }
        } else if entry.pathExtension.lowercased() == "bin", kind == nil || kind == .ggml {
          inFolder.append(WhisperModel(path: entry.path, name: entry.lastPathComponent,
                                       kind: .ggml, sizeBytes: fileSize(entry.path)))
        }
      }
      found.append(contentsOf: inFolder.sorted {
        $0.sizeBytes != $1.sizeBytes
          ? $0.sizeBytes > $1.sizeBytes
          : $0.name.localizedStandardCompare($1.name) == .orderedAscending
      })
    }
    var seen = Set<String>()
    return found.filter { seen.insert($0.path).inserted }
  }

  /// MLX 모델 폴더인가 — config.json + 가중치(safetensors/npz)
  static func mlxModel(at url: URL) -> WhisperModel? {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
    let config = url.appendingPathComponent("config.json")
    guard fm.fileExists(atPath: config.path) else { return nil }
    let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
    guard contents.contains(where: { $0.hasSuffix(".safetensors") || $0.hasSuffix(".npz") }) else { return nil }
    let size = contents.reduce(Int64(0)) { $0 + fileSize(url.appendingPathComponent($1).path) }
    return WhisperModel(path: url.path, name: url.lastPathComponent, kind: .mlx, sizeBytes: size)
  }

  public static func fileSize(_ path: String) -> Int64 {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
  }

  // MARK: - 백엔드·모델 확정

  /// 설정이 `auto`면 준비된 것 우선(품질 우선: mlx-whisper → whisper.cpp)
  public static func resolvedBackend(settings: QuickTalkSettings) -> WhisperBackend {
    if settings.whisperBackend != .auto { return settings.whisperBackend }
    if isReady(backend: .mlxWhisper, settings: settings) { return .mlxWhisper }
    if isReady(backend: .whisperCpp, settings: settings) { return .whisperCpp }
    return binaryPath(for: .mlxWhisper) != nil ? .mlxWhisper : .whisperCpp
  }

  /// 사용할 모델 경로 — 설정값이 있으면 그것, 없으면 감지 목록의 첫 번째(폴더 우선 · 큰 모델 우선)
  public static func modelPath(for backend: WhisperBackend, settings: QuickTalkSettings) -> String {
    switch backend {
    case .mlxWhisper:
      if !settings.whisperMLXModelPath.isEmpty { return settings.whisperMLXModelPath }
      if let m = detectModels(settings: settings, kind: .mlx).first { return m.path }
      return ""
    case .whisperCpp, .auto:
      if !settings.whisperModelPath.isEmpty { return settings.whisperModelPath }
      if let m = detectModels(settings: settings, kind: .ggml).first { return m.path }
      // 마지막 폴백: 앱 지원 폴더의 기본 모델(없으면 상태 문구로 안내된다)
      return VoiceService.whisperDefaultPath.path
    }
  }

  public static func isReady(backend: WhisperBackend, settings: QuickTalkSettings) -> Bool {
    guard binaryPath(for: backend) != nil else { return false }
    let model = modelPath(for: backend, settings: settings)
    return !model.isEmpty && FileManager.default.fileExists(atPath: model)
  }

  public static func isReady(settings: QuickTalkSettings) -> Bool {
    isReady(backend: resolvedBackend(settings: settings), settings: settings)
  }

  // MARK: - 상태 문구

  public static func statusLine(for backend: WhisperBackend, settings: QuickTalkSettings) -> String {
    guard let bin = binaryPath(for: backend) else {
      return Lf("%@ 없음 — %@", backend.shortName, backend.installHint)
    }
    let model = modelPath(for: backend, settings: settings)
    if model.isEmpty { return Lf("%@ OK(%@) · 모델 없음", backend.shortName, URL(fileURLWithPath: bin).lastPathComponent) }
    guard FileManager.default.fileExists(atPath: model) else {
      return Lf("%@ OK · 모델 없음 — %@", backend.shortName, model)
    }
    return Lf("%@ 사용 가능 (모델 %@)", backend.shortName, URL(fileURLWithPath: model).lastPathComponent)
  }

  /// 설정 화면·상태 카드용 한 줄 — 선택 백엔드 + 다른 백엔드 사용 가능 여부
  public static func status(settings: QuickTalkSettings) -> String {
    let backend = resolvedBackend(settings: settings)
    let line = statusLine(for: backend, settings: settings)
    guard settings.whisperBackend == .auto else { return line }
    let other: WhisperBackend = backend == .mlxWhisper ? .whisperCpp : .mlxWhisper
    guard isReady(backend: other, settings: settings) else { return line }
    return Lf("%@ · %@도 사용 가능", line, other.shortName)
  }

  /// 전사 언어 목록("" = 자동 감지)
  public static var languageOptions: [(String, String)] {
    [("", L("자동 감지")), ("ko", L("한국어")), ("en", L("영어")),
     ("ja", L("일본어")), ("zh", L("중국어")), ("es", L("스페인어")),
     ("fr", L("프랑스어")), ("de", L("독일어"))]
  }

  // MARK: - 실행 인자 (순수 함수 — 테스트 대상)

  public static func arguments(for backend: WhisperBackend,
                               model: String,
                               language: String,
                               wavPath: String,
                               outputDir: String) -> [String] {
    switch backend {
    case .whisperCpp, .auto:
      var args = ["-m", model, "-f", wavPath, "-nt", "-np"]
      if !language.isEmpty { args += ["-l", language] }
      return args
    case .mlxWhisper:
      var args = ["--model", model, "--output-format", "txt",
                  "--output-dir", outputDir, "--verbose", "False"]
      if !language.isEmpty { args += ["--language", language] }
      args.append(wavPath)
      return args
    }
  }

  /// mlx-whisper는 결과를 파일로 쓴다 — `<출력폴더>/<wav 이름>.txt`
  public static func readMLXTranscript(outputDir: URL, wav: URL) -> String? {
    let txt = outputDir.appendingPathComponent(wav.deletingPathExtension().lastPathComponent + ".txt")
    guard let text = try? String(contentsOf: txt, encoding: .utf8) else { return nil }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - 전사

  public static func transcribe(wavURL: URL, settings: QuickTalkSettings) async throws -> String {
    let backend = resolvedBackend(settings: settings)
    guard let bin = binaryPath(for: backend) else {
      NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 바이너리 없음 (%@)", backend.shortName)
      throw QuickTalkError.speechDenied()
    }
    let model = modelPath(for: backend, settings: settings)
    guard !model.isEmpty, FileManager.default.fileExists(atPath: model) else {
      NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 모델 없음 (%@)", backend.shortName)
      throw QuickTalkError.speechDenied()
    }

    // mlx-whisper는 파일 출력이라 임시 폴더가 필요하다
    var outputDir: URL?
    if backend == .mlxWhisper {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("quicktalk-whisper-\(UUID().uuidString)")
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      outputDir = dir
    }
    defer { if let dir = outputDir { try? FileManager.default.removeItem(at: dir) } }

    let args = arguments(for: backend, model: model, language: settings.whisperLanguage,
                         wavPath: wavURL.path, outputDir: outputDir?.path ?? "")
    let started = Date()
    let (status, stdout, stderr) = try await run(binary: bin, arguments: args)
    NSLog("[QuickTalk] Whisper 전사 — %@ %.1f초 (모델=%@, 종료=%d)",
          backend.shortName, Date().timeIntervalSince(started),
          URL(fileURLWithPath: model).lastPathComponent, status)

    switch backend {
    case .mlxWhisper:
      if let dir = outputDir, let text = readMLXTranscript(outputDir: dir, wav: wavURL), !text.isEmpty {
        return text
      }
      // 파일 출력이 없으면 stdout 폴백(JSON 덤프면 실패로 본다)
      let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if status == 0, !trimmed.isEmpty, !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") {
        return trimmed
      }
      NSLog("[ERROR] E-MAC-AUDIO-0001 mlx-whisper 전사 실패: %@", String(stderr.suffix(300)))
      throw QuickTalkError.speechDenied()
    case .whisperCpp, .auto:
      let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      guard status == 0, !trimmed.isEmpty else {
        NSLog("[ERROR] E-MAC-AUDIO-0001 whisper.cpp 전사 실패: %@", String(stderr.suffix(300)))
        throw QuickTalkError.speechDenied()
      }
      return trimmed
    }
  }

  /// 프로세스 실행 — 메인 밖에서 돌리고 stdout/stderr를 **동시에** 읽는다(파이프가 차서 멈추는 문제 방지)
  static func run(binary: String, arguments: [String]) async throws -> (Int32, String, String) {
    try await withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .userInitiated).async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = arguments
        proc.environment = processEnvironment()
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do { try proc.run() } catch {
          cont.resume(throwing: error); return
        }
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
          errData = errPipe.fileHandleForReading.readDataToEndOfFile()
          group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()
        cont.resume(returning: (proc.terminationStatus,
                                String(data: outData, encoding: .utf8) ?? "",
                                String(data: errData, encoding: .utf8) ?? ""))
      }
    }
  }

  /// 앱이 Finder로 실행되면 PATH가 최소라 ffmpeg·python을 못 찾는다 — 후보 경로를 앞에 붙인다
  static func processEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                 "\(home)/.local/bin", "\(home)/.venvs/mlx-whisper/bin"]
    var ordered: [String] = []
    for path in extra + (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
    where !ordered.contains(path) {
      ordered.append(path)
    }
    env["PATH"] = ordered.joined(separator: ":")
    return env
  }
}
