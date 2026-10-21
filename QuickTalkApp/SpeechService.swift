import Foundation
import AVFoundation
import Speech
import Combine

// Apple 음성: STT(SFSpeechRecognizer) + TTS(AVSpeechSynthesizer). 시스템 프레임워크만 사용.
final class AppleSpeechService: NSObject, ObservableObject {
  @Published var isRecording = false
  @Published var liveText = ""
  /// 읽어주기 재생 중 — 버튼이 **중지**로 바뀌고, 앱 어디서든 멈출 수 있게 공개한다
  @Published private(set) var isSpeaking = false

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()
  private let synthesizer = AVSpeechSynthesizer()
  var onPartial: ((String) -> Void)?
  var onFinal: ((String) -> Void)?

  // 설정(설정 창 › 음성)에서 오는 값 — 받아쓰기 언어 · 읽어주기 목소리/속도
  private var recognizerLocaleID = ""
  private var ttsVoiceID = ""
  private var ttsLanguage = "ko-KR"
  private var ttsRate: Float = 0.48

  override init() {
    super.init()
    synthesizer.delegate = self
    rebuildRecognizer()
  }

  /// 설정 변경 시 호출 — 받아쓰기 언어가 바뀌면 인식기를 다시 만든다.
  func configure(locale: String, voice: String, ttsLanguage: String, rate: Double) {
    if locale != recognizerLocaleID { rebuildRecognizer(localeID: locale) }
    ttsVoiceID = voice
    self.ttsLanguage = ttsLanguage
    let r = Float(rate)
    ttsRate = min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
  }

  /// 받아쓰기 언어 — 설정값이 시스템 지원 목록에 없으면 한국어 → 영어 → 첫 항목으로 폴백.
  private func rebuildRecognizer(localeID: String = "") {
    recognizerLocaleID = localeID
    let supported = SFSpeechRecognizer.supportedLocales().map { $0.identifier }
    var pick: String
    if !localeID.isEmpty, supported.contains(localeID) {
      pick = localeID
    } else {
      pick = ["ko-KR", "en-US"].first(where: { supported.contains($0) })
        ?? supported.first ?? "en-US"
      if !localeID.isEmpty {
        NSLog("[QuickTalk] 받아쓰기 언어 %@ 미지원 → %@ 사용", localeID, pick)
      }
    }
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: pick))
    NSLog("[QuickTalk] STT locale=%@ onDevice=%@", pick,
          (recognizer?.supportsOnDeviceRecognition ?? false) ? "Y" : "N")
  }

  /// 지금 설정으로 고른 목소리(없으면 그 언어에서 **가장 좋은 목소리** → 언어 기본 → 한국어 → 영어)
  private func currentVoice() -> AVSpeechSynthesisVoice? {
    if !ttsVoiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: ttsVoiceID) { return v }
    if let best = SpeechCatalog.voices(matching: ttsLanguage, from: Self.installedVoices()).first,
       let v = AVSpeechSynthesisVoice(identifier: best.id) {
      return v
    }
    return AVSpeechSynthesisVoice(language: ttsLanguage)
      ?? AVSpeechSynthesisVoice(language: "ko-KR")
      ?? AVSpeechSynthesisVoice(language: "en-US")
  }

  /// 설정 창의 목소리 후보 — 설치된 것 중에서 고른 언어만, 품질 높은 순.
  /// `super-compact`는 같은 목소리의 저품질 사본이라 품질 0으로 내려 뒤로 보낸다.
  static func installedVoices() -> [SpeechVoice] {
    AVSpeechSynthesisVoice.speechVoices().map { v in
      let quality: Int
      if v.quality == .premium { quality = 3 }
      else if v.quality == .enhanced { quality = 2 }
      else { quality = v.identifier.contains("super-compact") ? 0 : 1 }
      return SpeechVoice(id: v.identifier, name: v.name, language: v.language, quality: quality)
    }
  }

  func requestPermissions(completion: @escaping (Bool) -> Void) {
    // 받아쓰기·마이크 권한 대화상자가 대화 창(항상 위) 뒤로 숨지 않게 잠시 창을 내린다
    NotificationCenter.default.post(name: .quickTalkSystemPromptBegin, object: nil)
    SFSpeechRecognizer.requestAuthorization { sAuth in
      AVCaptureDevice.requestAccess(for: .audio) { mOK in
        DispatchQueue.main.async {
          NotificationCenter.default.post(name: .quickTalkSystemPromptEnd, object: nil)
          completion(sAuth == .authorized && mOK)
        }
      }
    }
  }

  func toggle() {
    isRecording ? stop() : start()
  }

  func start() {
    guard !isRecording else { return }
    requestPermissions { [weak self] ok in
      DispatchQueue.main.async {
        guard ok else {
          NSLog("[ERROR] E-MAC-AUDIO-0001 음성 권한 거부")
          return
        }
        self?.beginEngine()
      }
    }
  }

  private func beginEngine() {
    task?.cancel(); task = nil
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
    request = req
    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      NSLog("[ERROR] E-MAC-AUDIO-0001 오디오 엔진 시작 실패: \(error)")
      return
    }
    isRecording = true
    liveText = ""
    task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      if let result {
        DispatchQueue.main.async {
          self.liveText = result.bestTranscription.formattedString
          self.onPartial?(self.liveText)
          if result.isFinal {
            self.onFinal?(self.liveText)
            self.stop()
          }
        }
      }
      if error != nil {
        DispatchQueue.main.async { self.stop() }
      }
    }
  }

  func stop() {
    guard isRecording else { return }
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil; request = nil
    isRecording = false
  }

  // MARK: - TTS
  /// 읽어주기 — **항상 새로 읽는다**. 중지/전환 판단은 UIStore가 상태(`isSpeaking`)로 한다.
  /// (여기서 `synthesizer.isSpeaking`으로 토글하면, 방금 중지한 직후에도 true로 남아 있어
  ///  "다른 답변 읽기"가 무음으로 끝나는 문제가 있었다)
  func speak(_ text: String) {
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    synthesize(text)
  }

  /// 설정 창 '미리 듣기' — 지금 고른 목소리·속도로 짧게 읽어 준다(재생 중이면 끊고 새로)
  func previewVoice(_ sample: String = L("안녕하세요. QuickTalk입니다. 이 목소리로 답변을 읽어 드립니다.")) {
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    synthesize(sample)
  }

  private func synthesize(_ text: String) {
    let utt = AVSpeechUtterance(string: text)
    utt.voice = currentVoice()
    utt.rate = ttsRate
    synthesizer.speak(utt)
    // 콜백(didStart)을 기다리지 않고 즉시 반영 — 빠르게 두 번 눌러도 상태가 어긋나지 않는다
    isSpeaking = true
    NSLog("[QuickTalk] TTS voice=%@ locale=%@ rate=%.2f",
          utt.voice?.name ?? "default", utt.voice?.language ?? "-", ttsRate)
  }

  func stopSpeaking() {
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    // 중지는 즉시 UI에 반영한다(시스템 콜백은 조금 늦게 온다)
    if isSpeaking { isSpeaking = false }
  }
}

// MARK: - 재생 상태

extension AppleSpeechService: AVSpeechSynthesizerDelegate {
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in self?.isSpeaking = true }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in self?.isSpeaking = self?.synthesizer.isSpeaking ?? false }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in self?.isSpeaking = false }
  }
}
