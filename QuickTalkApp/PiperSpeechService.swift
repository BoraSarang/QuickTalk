import Foundation

// [INFO] [FEATURE] Piper TTS — 로컬 `piper` CLI로 WAV를 만들어 재생한다.
// 프로세스 실행·재생·정리는 `ProcessSpeechService`가 맡고, 여기서는 텍스트 파일과 인자만 만든다.
final class PiperSpeechService: ProcessSpeechService {
  private var rate: Double = 0.48
  private var modelSetting = ""
  private var binary = ""

  override var errorCode: String { "E-MAC-AUDIO-0003" }

  /// 설정 변경 반영(속도·모델·실행 파일 경로)
  func configure(rate: Double, model: String, binary: String) {
    self.rate = rate
    self.modelSetting = model
    self.binary = binary
  }

  override func makeJob(for text: String) -> Result<Job, SetupError> {
    guard let executable = PiperTTS.binaryPath(custom: binary) else {
      return .failure(SetupError(L("piper가 설치되지 않았습니다")))
    }
    guard let model = PiperTTS.modelPath(custom: modelSetting) else {
      return .failure(SetupError(L("Piper 모델(.onnx)을 찾지 못했습니다")))
    }

    let folder = FileManager.default.temporaryDirectory
    let output = folder.appendingPathComponent("quicktalk-piper-\(UUID().uuidString).wav")
    let input = folder.appendingPathComponent("quicktalk-piper-\(UUID().uuidString).txt")
    do {
      try text.write(to: input, atomically: true, encoding: .utf8)
    } catch {
      return .failure(SetupError(error.localizedDescription))
    }
    return .success(Job(executable: executable,
                        arguments: PiperTTS.arguments(model: model,
                                                      textFile: input.path,
                                                      outputPath: output.path,
                                                      rate: rate),
                        outputURL: output,
                        tempFiles: [input]))
  }
}
