import Foundation

// [INFO] [FEATURE] Edge TTS — `edge-tts` CLI로 mp3를 받아 재생한다.
// 프로세스 실행·재생·정리는 `ProcessSpeechService`가 맡고, 여기서는 인자만 만든다.
final class EdgeSpeechService: ProcessSpeechService {
  private var voice = EdgeTTS.defaultVoice
  private var rate: Double = 0.48
  private var binary = ""

  override var errorCode: String { "E-MAC-AUDIO-0002" }

  /// 설정 변경 반영(목소리·속도·실행 파일 경로)
  func configure(voice: String, rate: Double, binary: String) {
    self.voice = voice.isEmpty ? EdgeTTS.defaultVoice : voice
    self.rate = rate
    self.binary = binary
  }

  override func makeJob(for text: String) -> Result<Job, SetupError> {
    guard let executable = EdgeTTS.binaryPath(custom: binary) else {
      return .failure(SetupError(L("edge-tts가 설치되지 않았습니다")))
    }
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("quicktalk-edge-\(UUID().uuidString).mp3")
    return .success(Job(executable: executable,
                        arguments: EdgeTTS.arguments(text: text,
                                                     voice: voice,
                                                     ratePercent: EdgeTTS.ratePercent(fromRate: rate),
                                                     outputPath: output.path),
                        outputURL: output))
  }
}
