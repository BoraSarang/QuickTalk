import Foundation
import AVFoundation
import Combine

// [INFO] [REFACTOR] CLI 합성 TTS 공통 뼈대 (2026-10-20)
// Edge(`edge-tts`)와 Piper(`piper`)가 같은 흐름을 쓴다:
//   실행 파일·모델 확인 → 임시 오디오 파일 → 프로세스 실행 → AVAudioPlayer 재생 → 정리
// 하위 클래스는 `makeJob(for:)` 하나만 구현한다.

/// 프로세스로 오디오 파일을 합성해 재생하는 TTS 서비스의 공통 구현.
///
/// - 합성 중에도 `isSpeaking`이 true라 버튼이 즉시 ⏹으로 바뀐다.
/// - `stop()`은 실행 중인 프로세스를 종료하고 재생·임시 파일을 정리한다.
/// - 실패는 `lastError`(설정 '최근 오류')와 `errorCode` 로그로 남는다.
class ProcessSpeechService: NSObject, ObservableObject {
  /// 준비 단계 실패(실행 파일·모델 없음 등) — 사유 문구를 담는다
  struct SetupError: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  /// 하위 클래스가 만드는 합성 작업 한 건
  struct Job {
    let executable: URL
    let arguments: [String]
    /// 합성 결과(재생 후 지운다)
    let outputURL: URL
    /// 입력 텍스트 파일 등 중간 산출물(재생 후 지운다)
    var tempFiles: [URL] = []
  }

  /// 재생(또는 합성) 중 — 버튼이 **중지**로 바뀐다
  @Published private(set) var isSpeaking = false
  /// 마지막 실패 사유(설정 진단용). 성공하면 지운다.
  @Published private(set) var lastError: String?

  /// 실패 로그 코드 — 하위 클래스에서 지정한다.
  var errorCode: String { "E-MAC-AUDIO-0002" }

  private var process: Process?
  private var player: AVAudioPlayer?
  private var job: Job?
  /// 요청 세대 — stop()/새 요청이 이전 완료 콜백을 무효화한다
  private var runID = 0

  // MARK: - 하위 클래스 훅

  /// 실행 파일·모델을 확인하고 합성 작업을 만든다. 실패하면 사유를 담아 돌려준다.
  func makeJob(for text: String) -> Result<Job, SetupError> {
    .failure(SetupError(L("구현되지 않음")))
  }

  // MARK: - 공개 API

  /// 읽어주기 — 항상 새로 합성·재생한다(중지 판단은 UIStore가 상태로 한다).
  func speak(_ text: String) {
    guard !text.isEmpty else { return }
    start(text)
  }

  /// 설정 창 '미리 듣기' — 짧은 샘플
  func previewVoice(_ sample: String = L("안녕하세요. QuickTalk입니다. 이 목소리로 답변을 읽어 드립니다.")) {
    start(sample)
  }

  /// 즉시 중지 — 합성 중이면 프로세스를 끝내고, 재생 중이면 멈춘다.
  func stop() {
    runID += 1
    if let p = process, p.isRunning { p.terminate() }
    process = nil
    player?.stop()
    player = nil
    cleanup()
    if isSpeaking { isSpeaking = false }
  }

  // MARK: - 합성 → 재생

  private func start(_ text: String) {
    stop()
    switch makeJob(for: text) {
    case .failure(let error):
      lastError = error.message
      NSLog("[ERROR] %@ TTS 준비 실패 — %@", errorCode, error.message)
    case .success(let job):
      begin(job)
    }
  }

  private func begin(_ job: Job) {
    runID += 1
    let id = runID
    self.job = job
    lastError = nil
    isSpeaking = true               // 합성 중에도 중지할 수 있게 바로 반영

    let p = Process()
    p.executableURL = job.executable
    p.arguments = job.arguments
    let errPipe = Pipe()
    p.standardError = errPipe
    p.standardOutput = FileHandle.nullDevice   // 읽지 않는 파이프가 차서 멈추지 않게
    process = p

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var failure: String?
      do {
        try p.run()
        // stderr를 EOF(자식 종료)까지 먼저 읽는다 — 64KB를 넘겨도 파이프가 차서 교착되지 않게
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
          let raw = String(data: data, encoding: .utf8) ?? ""
          failure = raw.isEmpty ? "exit \(p.terminationStatus)" : raw
        }
      } catch {
        failure = error.localizedDescription
      }
      DispatchQueue.main.async {
        guard let self, self.runID == id else { return }
        self.process = nil
        if let failure {
          self.finish(error: failure)
        } else {
          self.play(job.outputURL)
        }
      }
    }
  }

  private func play(_ url: URL) {
    do {
      let p = try AVAudioPlayer(contentsOf: url)
      p.delegate = self
      player = p
      p.play()
      isSpeaking = true
    } catch {
      finish(error: error.localizedDescription)
    }
  }

  private func finish(error: String?) {
    if let error {
      lastError = error
      NSLog("[ERROR] %@ TTS 실패 — %@", errorCode, error)
    }
    player?.stop()
    player = nil
    cleanup()
    if isSpeaking { isSpeaking = false }
  }

  private func cleanup() {
    guard let job else { return }
    let fm = FileManager.default
    try? fm.removeItem(at: job.outputURL)
    for url in job.tempFiles { try? fm.removeItem(at: url) }
    self.job = nil
  }
}

extension ProcessSpeechService: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    finish(error: flag ? nil : L("재생을 끝까지 하지 못했습니다"))
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    finish(error: error?.localizedDescription ?? L("오디오를 읽지 못했습니다"))
  }
}
