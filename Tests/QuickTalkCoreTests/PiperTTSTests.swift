import XCTest
@testable import QuickTalkCore

/// Piper TTS(로컬) — 모델·실행 파일 탐색, 속도 환산, CLI 인자 (2026-10-20, T-60).
final class PiperTTSTests: XCTestCase {

  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("piper-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  // MARK: - 속도 → length-scale

  func testLengthScaleIsInverseOfRate() {
    XCTAssertEqual(PiperTTS.lengthScale(fromRate: 0.48), 1.00)   // 기본 = 1.00
    XCTAssertEqual(PiperTTS.lengthScale(fromRate: 0.62), 0.77)   // 빠르게
    XCTAssertEqual(PiperTTS.lengthScale(fromRate: 0.35), 1.37)   // 느리게
  }

  func testLengthScaleIsClamped() {
    XCTAssertEqual(PiperTTS.lengthScale(fromRate: 0.01), 1.45)
    XCTAssertEqual(PiperTTS.lengthScale(fromRate: 10), 0.70)
  }

  func testLengthScaleArgumentUsesDotDecimal() {
    XCTAssertEqual(PiperTTS.lengthScaleArgument(fromRate: 0.48), "1.00")
    XCTAssertEqual(PiperTTS.lengthScaleArgument(fromRate: 0.62), "0.77")
  }

  // MARK: - 모델 탐색

  func testOnnxFilesAreSortedAndFiltered() throws {
    for name in ["b_voice.onnx", "a_voice.onnx", "notes.txt", "c_voice.onnx.json"] {
      FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("x".utf8))
    }
    let names = PiperTTS.onnxFiles(in: folder.path).map { ($0 as NSString).lastPathComponent }
    XCTAssertEqual(names, ["a_voice.onnx", "b_voice.onnx"])
  }

  func testModelPathAcceptsFolder() throws {
    let model = folder.appendingPathComponent("ko_KR-kss-medium.onnx")
    FileManager.default.createFile(atPath: model.path, contents: Data("x".utf8))
    XCTAssertEqual(PiperTTS.modelPath(custom: folder.path)?.path, model.path)
  }

  func testModelPathAcceptsFile() throws {
    let model = folder.appendingPathComponent("voice.onnx")
    FileManager.default.createFile(atPath: model.path, contents: Data("x".utf8))
    XCTAssertEqual(PiperTTS.modelPath(custom: model.path)?.path, model.path)
  }

  func testConfigPathOnlyWhenJSONExists() throws {
    let model = folder.appendingPathComponent("voice.onnx")
    FileManager.default.createFile(atPath: model.path, contents: Data("x".utf8))
    XCTAssertNil(PiperTTS.configPath(for: model))
    FileManager.default.createFile(atPath: model.path + ".json", contents: Data("{}".utf8))
    XCTAssertEqual(PiperTTS.configPath(for: model)?.path, model.path + ".json")
  }

  // MARK: - CLI 인자

  func testArgumentsIncludeModelInputOutputAndRate() throws {
    let model = folder.appendingPathComponent("voice.onnx")
    FileManager.default.createFile(atPath: model.path, contents: Data("x".utf8))
    let args = PiperTTS.arguments(model: model, textFile: "/tmp/in.txt", outputPath: "/tmp/out.wav", rate: 0.48)
    XCTAssertEqual(args.first, "-m")
    XCTAssertTrue(args.contains(model.path))
    XCTAssertTrue(args.contains("/tmp/in.txt"))
    XCTAssertTrue(args.contains("/tmp/out.wav"))
    XCTAssertEqual(args[args.firstIndex(of: "--length-scale")! + 1], "1.00")
    XCTAssertFalse(args.contains("-c"))     // json이 없으면 넘기지 않는다
  }

  func testArgumentsIncludeConfigWhenPresent() throws {
    let model = folder.appendingPathComponent("voice.onnx")
    FileManager.default.createFile(atPath: model.path, contents: Data("x".utf8))
    FileManager.default.createFile(atPath: model.path + ".json", contents: Data("{}".utf8))
    let args = PiperTTS.arguments(model: model, textFile: "/tmp/in.txt", outputPath: "/tmp/out.wav", rate: 0.48)
    XCTAssertEqual(args[args.firstIndex(of: "-c")! + 1], model.path + ".json")
  }

  // MARK: - 엔진·설정

  func testPiperIsAThirdEngine() {
    XCTAssertEqual(TTSEngine.piper.rawValue, "piper")
    XCTAssertEqual(TTSEngine.allCases.count, 3)
    XCTAssertFalse(TTSEngine.piper.displayName.isEmpty)
    XCTAssertFalse(TTSEngine.piper.shortName.isEmpty)
  }

  func testSettingsPiperDefaultsAndRoundTrip() throws {
    var s = QuickTalkSettings()
    XCTAssertEqual(s.piperModelPath, "")
    XCTAssertEqual(s.piperBinaryPath, "")
    s.piperModelPath = "/tmp/ko.onnx"
    s.piperBinaryPath = "/tmp/piper"
    s.ttsEngine = .piper
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(back.piperModelPath, "/tmp/ko.onnx")
    XCTAssertEqual(back.piperBinaryPath, "/tmp/piper")
    XCTAssertEqual(back.ttsEngine, .piper)
  }
}
