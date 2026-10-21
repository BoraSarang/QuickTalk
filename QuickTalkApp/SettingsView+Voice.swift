import SwiftUI
import Speech
import AVFoundation
import UniformTypeIdentifiers

// [REFACTOR] SettingsView — 음성(받아쓰기·TTS·Whisper·Piper) 섹션 (2026-10-20 파일 분리)
extension SettingsView {
  // MARK: - 음성

  @ViewBuilder
  var voiceSection: some View {
    groupBox(L("엔진")) {
      pickerRow(L("받아쓰기 엔진"), selection: $store.settings.voiceEngine,
                options: VoiceEngine.allCases.map { ($0, $0.displayName) })
      caption(L("Apple은 설치된 시스템 음성인식을 씁니다. Whisper는 로컬 모델·바이너리가 필요합니다(mlx-whisper·whisper.cpp 모두 지원)."))
      pickerRow(L("읽어주기 엔진"), selection: $store.settings.ttsEngine,
                options: TTSEngine.allCases.map { ($0, $0.displayName) })
      caption(L("Apple 음성은 오프라인 시스템 목소리, Edge TTS는 마이크로소프트 신경망 목소리를 온라인으로 받아 재생합니다. Piper는 내려받은 모델로 완전 오프라인 합성합니다."))
    }
    groupBox(L("Apple 음성")) {
      pickerRow(L("받아쓰기 언어"), selection: $store.settings.appleSpeechLocale,
                options: speechLocaleOptions)
      caption(L("시스템 음성인식이 지원하는 언어만 나옵니다. '시스템 기본'은 한국어 → 영어 순으로 고릅니다."))
      if store.settings.ttsEngine == .apple {
        pickerRow(L("읽어주기 언어"), selection: ttsLanguageBinding,
                  options: ttsLanguageOptions)
        HStack {
          Text(L("읽어주기 목소리")).font(.body)
          Spacer(minLength: 12)
          Picker("", selection: $store.settings.ttsVoiceID) {
            Text(L("자동 (가장 좋은 목소리)")).tag("")
            ForEach(ttsVoices) { v in Text(v.displayName).tag(v.id) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(minWidth: 220, maxWidth: 320, alignment: .trailing)
          Button(L("미리 듣기")) { store.previewVoice() }
            .help(L("지금 고른 목소리·속도로 짧게 읽어 봅니다"))
        }
        .padding(.vertical, 2)
        ttsRateRow(note: nil)
        valueRow(L("받아쓰기"), L("마이크 버튼 = 실시간 전사 → 입력창 삽입"))
        valueRow(L("읽어주기"), L("답변의 ▶ 버튼 = TTS 재생"))
        caption(L("목소리가 로봇 같으면 '향상(Siri 자연스러운)' 또는 '프리미엄' 목소리를 고르세요. '자동'은 설치된 것 중 가장 좋은 품질을 씁니다. 더 내려받으려면 시스템 설정 › 손쉬운 사용 › 콘텐츠 말하기 › 시스템 목소리 관리."))
        caption(L("첫 실행 시 마이크·음성인식 권한을 요청합니다."))
      } else {
        caption(Lf("지금은 %@로 읽습니다 — 아래 설정에서 목소리를 고르세요.",
                   store.settings.ttsEngine.shortName))
        valueRow(L("받아쓰기"), L("마이크 버튼 = 실시간 전사 → 입력창 삽입"))
        caption(L("첫 실행 시 마이크·음성인식 권한을 요청합니다."))
      }
    }
    if store.settings.ttsEngine == .edge {
      groupBox(L("Edge TTS (온라인)")) {
        pickerRow(L("목소리"), selection: $store.settings.edgeVoice, options: edgeVoiceOptions)
        HStack(spacing: 8) {
          Text(L("직접 입력")).font(.callout).foregroundColor(.secondary)
          TextField("", text: $store.settings.edgeVoice,
                    prompt: Text(L("목소리 ID (예: ko-KR-SunHiNeural)")))
            .font(.callout)
            .help(L("목록에 없는 목소리도 ID로 지정할 수 있습니다"))
        }
        caption(L("한국어·영어·일본어·중국어 신경망 목소리입니다. 전체 목록은 터미널에서 `edge-tts --list-voices`."))
        ttsRateRow(note: EdgeTTS.rateArgument(percent: EdgeTTS.ratePercent(fromRate: store.settings.ttsRate)))
        HStack(spacing: 10) {
          Text(L("실행 파일")).font(.body)
          TextField("", text: $store.settings.edgeBinaryPath,
                    prompt: Text(L("자동 탐색 (~/.venvs/edge-tts/bin · Homebrew)")))
          Button(L("미리 듣기")) { store.previewVoice() }
            .help(L("지금 고른 목소리·속도로 짧게 읽어 봅니다"))
        }
        valueRow(L("상태"), EdgeTTS.status(custom: store.settings.edgeBinaryPath))
        if let err = store.edgeSpeech.lastError {
          valueRow(L("최근 오류"), err)
        }
        caption(L("네트워크가 필요하고 합성에 1초 안팎 걸립니다. 설치: python3 -m venv ~/.venvs/edge-tts && ~/.venvs/edge-tts/bin/pip install edge-tts"))
        caption(L("Edge 서버에 닿지 않으면 재생되지 않습니다(로그 E-MAC-AUDIO-0002). 그때는 Apple 음성으로 바꿔 쓰세요."))
      }
    }
    if store.settings.ttsEngine == .piper {
      groupBox(L("Piper (로컬·오프라인)")) {
        let resolvedModel = PiperTTS.modelPath(custom: store.settings.piperModelPath)
        valueRow(L("모델"), resolvedModel?.lastPathComponent ?? L("찾지 못함 — 아래에서 선택하세요"))
        HStack(spacing: 8) {
          TextField("", text: $store.settings.piperModelPath,
                    prompt: Text(L("모델 경로 또는 폴더 (비우면 자동 탐색)")))
            .font(.callout)
          Button(L("선택…")) { showPiperPicker = true }
        }
        ttsRateRow(note: "×" + PiperTTS.lengthScaleArgument(fromRate: store.settings.ttsRate))
        HStack(spacing: 10) {
          Text(L("실행 파일")).font(.body)
          TextField("", text: $store.settings.piperBinaryPath,
                    prompt: Text(L("자동 탐색 (~/.venvs/piper/bin · Homebrew)")))
          Button(L("미리 듣기")) { store.previewVoice() }
            .help(L("지금 고른 모델·속도로 짧게 읽어 봅니다"))
        }
        valueRow(L("상태"), PiperTTS.status(binary: store.settings.piperBinaryPath,
                                          model: store.settings.piperModelPath))
        if let err = store.piperSpeech.lastError {
          valueRow(L("최근 오류"), err)
        }
        caption(L("기본 탐색: ~/Documents/Files/piper-ko-eva · ~/Documents/Files/piper · ~/Library/Application Support/QuickTalk/piper"))
        caption(L("설치: python3 -m venv ~/.venvs/piper && ~/.venvs/piper/bin/pip install piper-tts — 모델은 .onnx와 .onnx.json을 같은 폴더에 두세요."))
        caption(L("네트워크 없이 동작합니다. 합성은 1초 안팎 걸리고, 첫 실행은 모델 로딩 때문에 조금 더 걸릴 수 있습니다."))
      }
      .fileImporter(isPresented: $showPiperPicker,
                    allowedContentTypes: [.item, .folder]) { res in
        if case .success(let url) = res {
          store.settings.piperModelPath = url.path
        }
      }
    }
    groupBox(L("Whisper (로컬)")) {
      pickerRow(L("백엔드"), selection: $store.settings.whisperBackend,
                options: WhisperBackend.allCases.map { ($0, $0.displayName) })
      pickerRow(L("언어"), selection: $store.settings.whisperLanguage,
                options: WhisperService.languageOptions)
      valueRow(L("상태"), WhisperService.status(settings: store.settings))
      whisperModelRow(L("whisper.cpp 모델"), kind: .ggml, selection: $store.settings.whisperModelPath)
      whisperModelRow(L("mlx-whisper 모델"), kind: .mlx, selection: $store.settings.whisperMLXModelPath)
      HStack {
        TextField("", text: $store.settings.whisperModelFolder,
                  prompt: Text(L("모델 폴더 (비우면 기본 위치)")))
        Button(L("선택…")) { showWhisperFolderPicker = true }
      }
      caption(L("기본 탐색 폴더: ~/Documents/Files/whisper · ~/Library/Application Support/QuickTalk/models"))
      caption(L("whisper.cpp는 ggml-*.bin 파일, mlx-whisper는 config.json + 가중치 폴더를 씁니다. 모델을 비우면 감지된 것 중 **가장 큰 모델**을 자동으로 씁니다."))
        .fileImporter(isPresented: $showWhisperPicker,
                      allowedContentTypes: whisperPickKind == .ggml ? [.item] : [.folder, .item]) { res in
          if case .success(let url) = res {
            if whisperPickKind == .ggml { store.settings.whisperModelPath = url.path }
            else { store.settings.whisperMLXModelPath = url.path }
          }
        }
        .fileImporter(isPresented: $showWhisperFolderPicker, allowedContentTypes: [.folder]) { res in
          if case .success(let url) = res { store.settings.whisperModelFolder = url.path }
        }
    }
  }

  /// 읽어주기 속도 행 — 두 엔진이 같은 슬라이더를 쓴다(Edge는 퍼센트를 함께 보여 준다)
  private func ttsRateRow(note: String?) -> some View {
    HStack(spacing: 10) {
      Text(L("읽어주기 속도")).font(.body)
      Slider(value: $store.settings.ttsRate, in: 0.35...0.62, step: 0.01)
        .frame(minWidth: 140, maxWidth: 220)
      Text(note ?? ttsRateLabel)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(minWidth: 48, alignment: .leading)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
  }

  /// Edge TTS 목소리 — 목록에 없던 ID도 선택이 사라지지 않게 앞에 넣는다
  private var edgeVoiceOptions: [(String, String)] {
    var list = EdgeTTS.voices.map { ($0.id, $0.displayName) }
    let current = store.settings.edgeVoice
    if !current.isEmpty, !list.contains(where: { $0.0 == current }) {
      list.insert((current, current), at: 0)
    }
    return list
  }

  /// 받아쓰기 언어 — 시스템 음성인식이 지원하는 목록(표시 이름 순)
  private var speechLocaleOptions: [(String, String)] {
    let ids = SFSpeechRecognizer.supportedLocales().map { $0.identifier }
    let sorted = ids
      .sorted { SpeechCatalog.languageName($0).localizedStandardCompare(SpeechCatalog.languageName($1)) == .orderedAscending }
      .map { ($0, SpeechCatalog.languageName($0)) }
    return [("", L("시스템 기본 (한국어)"))] + sorted
  }

  /// 읽어주기 언어 — **설치된 목소리가 있는 언어**만(목소리 없는 언어를 고르면 무음이 된다)
  private var ttsLanguageOptions: [(String, String)] {
    var ids = SpeechCatalog.languages(from: AppleSpeechService.installedVoices())
    let current = store.settings.ttsLanguage
    if !current.isEmpty, !ids.contains(current) { ids.insert(current, at: 0) }
    return ids.map { ($0, SpeechCatalog.languageName($0)) }
  }

  /// 읽어주기 언어를 바꾸면 목소리도 그 언어 기본으로 되돌린다(다른 언어 목소리가 남지 않게)
  private var ttsLanguageBinding: Binding<String> {
    Binding(get: { store.settings.ttsLanguage }, set: { newValue in
      store.settings.ttsLanguage = newValue
      if !store.settings.ttsVoiceID.isEmpty { store.settings.ttsVoiceID = "" }
    })
  }

  /// 고른 언어의 목소리 — 품질(프리미엄·향상) 높은 순
  private var ttsVoices: [SpeechVoice] {
    let all = AppleSpeechService.installedVoices()
    var list = SpeechCatalog.voices(matching: store.settings.ttsLanguage, from: all)
    let id = store.settings.ttsVoiceID
    if !id.isEmpty, !list.contains(where: { $0.id == id }), let extra = all.first(where: { $0.id == id }) {
      list.insert(extra, at: 0)       // 예전에 고른 목소리가 목록에 없어도 선택이 사라지지 않게
    }
    return list
  }

  private var ttsRateLabel: String {
    switch store.settings.ttsRate {
    case ..<0.42: return L("느리게")
    case ..<0.53: return L("보통")
    default: return L("빠르게")
    }
  }

  /// 모델 선택 행 — 검색 폴더에서 찾은 모델 드롭다운 + 경로 직접 지정
  private func whisperModelRow(_ label: String, kind: WhisperModel.Kind, selection: Binding<String>) -> some View {
    let models = WhisperService.detectModels(settings: store.settings, kind: kind)
    let backend: WhisperBackend = kind == .ggml ? .whisperCpp : .mlxWhisper
    let resolved = WhisperService.modelPath(for: backend, settings: store.settings)
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(label).font(.body)
        Spacer(minLength: 12)
        Picker("", selection: selection) {
          Text(models.isEmpty ? L("감지된 모델 없음") : L("자동 (감지된 모델)")).tag("")
          ForEach(models) { m in Text("\(m.name) · \(m.sizeText)").tag(m.path) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 200, maxWidth: 300, alignment: .trailing)
      }
      HStack {
        TextField("", text: selection, prompt: Text(L("경로 직접 지정")))
        Button(L("선택…")) { whisperPickKind = kind; showWhisperPicker = true }
      }
      caption(Lf("현재: %@", resolved.isEmpty ? L("없음") : resolved))
    }
  }

}
