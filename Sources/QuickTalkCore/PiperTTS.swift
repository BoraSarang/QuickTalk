import Foundation

// [INFO] [FEATURE] Piper TTS — 로컬 신경망 음성(오프라인). `piper` CLI로 WAV를 만들어 재생한다.

/// Piper(https://github.com/rhasspy/piper) 실행 파일·모델 탐색과 CLI 인자 구성.
/// 앱은 이 정보로 `piper -m model.onnx -i text.txt -f out.wav`를 실행한다.
public enum PiperTTS {
  public static let defaultSample = "안녕하세요. QuickTalk입니다. 이 목소리로 답변을 읽어 드립니다."

  /// 실행 파일 후보 — Finder에서 띄운 앱은 PATH가 최소라 절대 경로로 찾는다.
  public static func binaryPath(custom: String = "") -> URL? {
    var candidates: [String] = []
    let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { candidates.append(trimmed) }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    candidates += [
      "\(home)/.venvs/piper/bin/piper",
      "\(home)/.local/bin/piper",
      "/opt/homebrew/bin/piper",
      "/usr/local/bin/piper",
    ]
    guard let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else { return nil }
    return URL(fileURLWithPath: hit)
  }

  public static func isInstalled(custom: String = "") -> Bool {
    binaryPath(custom: custom) != nil
  }

  /// 모델(.onnx) 경로 — 직접 지정이 폴더면 그 안의 onnx를, 비어 있으면 기본 폴더를 뒤진다.
  public static func modelPath(custom: String = "") -> URL? {
    let fm = FileManager.default
    let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [String] = []
    if !trimmed.isEmpty {
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: trimmed, isDirectory: &isDir) {
        if isDir.boolValue { candidates += onnxFiles(in: trimmed) } else { candidates.append(trimmed) }
      }
    }
    let home = fm.homeDirectoryForCurrentUser.path
    let folders = [
      "\(home)/Documents/Files/piper-ko-eva",
      "\(home)/Documents/Files/piper",
      "\(home)/Library/Application Support/QuickTalk/piper",
      "\(home)/.local/share/piper",
    ]
    for folder in folders { candidates += onnxFiles(in: folder) }
    guard let hit = candidates.first(where: { fm.fileExists(atPath: $0) }) else { return nil }
    return URL(fileURLWithPath: hit)
  }

  /// 폴더 안의 onnx — 이름순(여러 개면 첫 번째를 쓴다)
  public static func onnxFiles(in folder: String) -> [String] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
    return names.filter { $0.hasSuffix(".onnx") }.sorted().map { "\(folder)/\($0)" }
  }

  /// 모델에 딸린 설정 파일(`model.onnx.json`) — 있으면 `-c`로 넘긴다.
  public static func configPath(for model: URL) -> URL? {
    let path = model.path + ".json"
    return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
  }

  public static var isReady: Bool { isInstalled() && modelPath() != nil }

  /// 설정 창 상태 행 — 실행 파일과 모델을 함께 보여 준다.
  public static func status(binary: String = "", model: String = "") -> String {
    guard let exe = binaryPath(custom: binary) else { return L("설치되지 않음 — piper 실행 파일을 찾지 못했습니다") }
    guard let m = modelPath(custom: model) else { return Lf("모델 없음 — 실행 파일은 있음 (%@)", exe.path) }
    return Lf("준비됨 — %@", m.path)
  }

  /// 설정 속도(0.35~0.62, Apple 기준) → Piper `--length-scale`.
  /// length-scale은 **클수록 느리다** — 속도와 반비례. 기본 0.48 ≈ 1.00.
  public static func lengthScale(fromRate rate: Double) -> Double {
    let raw = 0.48 / max(rate, 0.01)
    let clamped = min(max(raw, 0.70), 1.45)
    return (clamped * 100).rounded() / 100
  }

  /// `--length-scale` 표시/인자 — 소수 둘째 자리 고정(로케일 영향 없이 점 사용).
  public static func lengthScaleArgument(fromRate rate: Double) -> String {
    String(format: "%.2f", lengthScale(fromRate: rate))
  }

  /// piper CLI 인자 — 텍스트는 파일로 넘겨 인자 길이 제한을 피한다.
  public static func arguments(model: URL,
                               textFile: String,
                               outputPath: String,
                               rate: Double) -> [String] {
    var args = ["-m", model.path,
                "-i", textFile,
                "-f", outputPath,
                "--length-scale", lengthScaleArgument(fromRate: rate)]
    if let config = configPath(for: model) { args += ["-c", config.path] }
    return args
  }
}
