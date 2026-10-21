import Foundation

// [FEATURE] 대화 기억 정리 (T-71)
//
// 대화가 길어지면 원격·Ollama는 매 턴 전체 기록을 다시 보내 첫 토큰이 늦어지고 비용이 커진다.
// Apple FM은 컨텍스트가 4,096토큰이라 더 빨리 한계에 닿는다.
// 해결: **최근 몇 턴만 원문으로 남기고, 그 이전은 요약 1개로 대체**한다.
// - 원문 턴은 삭제하지 않는다(화면·검색·보관함은 그대로).
// - 요약은 `Conversation.summary`에 저장하고, 경계(`summaryThroughTurnID`) 이후만 원문 전송.
// - 여기 있는 함수는 순수 계산이라 테스트가 직접 검증한다.
public enum ConversationMemory {
  /// 입력 예산의 70%를 넘으면 정리한다 — 100%에 닿기 전에 여유를 남긴다.
  public static let triggerRatio = 0.70

  // MARK: - 토큰 추정

  /// 보수적 토큰 추정 — 한국어/한자/일본어는 **1자 ≈ 1토큰**(Apple 문서 기준),
  /// ASCII는 4자 ≈ 1토큰으로 센다. 정확한 토크나이저가 아니라 예산 판단용이다.
  public static func estimateTokens(_ text: String) -> Int {
    guard !text.isEmpty else { return 0 }
    var tokens = 0
    var asciiRun = 0
    for scalar in text.unicodeScalars {
      if scalar.isASCII {
        asciiRun += 1
        if asciiRun == 4 {
          tokens += 1
          asciiRun = 0
        }
      } else {
        if asciiRun > 0 {
          tokens += 1
          asciiRun = 0
        }
        tokens += 1
      }
    }
    if asciiRun > 0 { tokens += 1 }
    return tokens
  }

  /// 턴 1개 — 본문 + 첨부 이름 + 메시지당 고정 오버헤드(역할·구분자).
  public static func estimateTokens(_ turn: Turn) -> Int {
    var n = 4 + estimateTokens(turn.text)
    for a in turn.attachments {
      n += estimateTokens(a.name) + 2
    }
    return n
  }

  /// 턴 묶음.
  public static func estimateTokens(_ turns: [Turn]) -> Int {
    turns.reduce(0) { $0 + estimateTokens($1) }
  }

  // MARK: - 프로바이더 예산

  /// 모델의 전체 컨텍스트(토큰). 사용자가 프로바이더에 값을 넣었으면 그 값을 쓴다.
  public static func totalBudget(for provider: LLMProviderConfig) -> Int {
    switch provider.type {
    case .appleFM:
      return 4_096                       // Foundation Models 고정 한도
    case .ollama:
      return max(1_024, provider.contextTokens ?? 8_192)
    case .openAICompatible:
      return max(2_048, provider.contextTokens ?? 32_768)
    }
  }

  /// 입력에 쓸 수 있는 토큰 — 출력·지시문 몫을 먼저 떼어 둔다.
  public static func inputBudget(for provider: LLMProviderConfig) -> Int {
    let total = totalBudget(for: provider)
    let outputReserve = min(2_048, max(512, total / 4))
    let instructionReserve = 256
    return max(512, total - outputReserve - instructionReserve)
  }

  /// 로컬 Ollama 기본 문맥 상한 — 32B Q4 실측이 **프롬프트 72~140 tok/s · 생성 3.8~4.5 tok/s**라
  /// 문맥이 길면 첫 토큰까지 분 단위로 걸린다(Model 8,192 기준 4,000토큰 ≈ 40초).
  /// 모델이 받을 수 있는 양(8,192)과 별개로, **앱이 보내는 양**을 줄이는 값이다.
  public static let localOllamaPromptBudget = 3_072

  /// 요청에 실제로 싣는 문맥 예산. 로컬 모델은 기본값일 때만 줄이고,
  /// 사용자가 프로바이더에 컨텍스트 토큰을 직접 지정했으면 그 의도를 존중한다.
  public static func promptBudget(for provider: LLMProviderConfig) -> Int {
    let base = inputBudget(for: provider)
    switch provider.type {
    case .ollama:
      guard provider.contextTokens == nil else { return base }
      return min(base, localOllamaPromptBudget)
    case .appleFM, .openAICompatible:
      return base
    }
  }

  /// 지금 요청에 실릴 토큰 — 요약이 있으면 `요약 + 경계 이후 원문`만 센다.
  public static func contextTokens(_ conversation: Conversation) -> Int {
    if let summary = conversation.activeSummary,
       let boundary = conversation.summaryBoundaryIndex {
      let recent = Array(conversation.turns[(boundary + 1)...])
      return 16 + estimateTokens(summary) + estimateTokens(recent)
    }
    return estimateTokens(conversation.turns)
  }

  /// 요청에 실을 기록 — 요약 경계 이후의 원문만 남긴다.
  /// `droppingLast`는 방금 추가된 사용자 턴을 빼기 위한 것(이번 질문은 프롬프트로 따로 실린다).
  public static func requestHistory(_ conversation: Conversation,
                                    droppingLast: Bool = true) -> [Turn] {
    guard let boundary = conversation.summaryBoundaryIndex else {
      return droppingLast ? Array(conversation.turns.dropLast()) : conversation.turns
    }
    let start = min(conversation.turns.count, boundary + 1)
    let recent = Array(conversation.turns[start...])
    return droppingLast ? Array(recent.dropLast()) : recent
  }

  /// 요약을 프롬프트 앞에 고정한다 — Apple FM의 6턴 제한에 잘리지 않게.
  public static func memoryPromptPrefix(_ conversation: Conversation) -> String {
    guard let summary = conversation.activeSummary else { return "" }
    return "이전 대화 요약(사실·결정·선호):\n\(summary)\n\n"
  }

  /// 이번 요청에 실을 기록을 예산에 맞춘다 — 최근 원문 자체가 예산을 넘는 극단적 장문 대화의
  /// **강제 축약** 경로다. 저장된 원문은 건드리지 않고, 요청에서만 오래된 턴부터 뺀다.
  ///
  /// `prompt`(이번 질문)·요약·첨부 오버헤드를 먼저 예약하고, 남은 예산에 들어갈 때까지
  /// 기록의 앞쪽을 버린다. 반환값의 `dropped`는 UI 안내에 쓴다.
  public static func fitHistory(_ conversation: Conversation,
                                prompt: String,
                                provider: LLMProviderConfig,
                                attachmentTokens: Int = 0,
                                extraTokens: Int = 0,
                                maxRatio: Double = 0.95) -> (history: [Turn], dropped: Int) {
    let history = requestHistory(conversation)
    let budget = max(512, Int(Double(promptBudget(for: provider)) * maxRatio))
    let fixed = estimateTokens(prompt)
      + estimateTokens(memoryPromptPrefix(conversation))
      + max(0, attachmentTokens)
      + max(0, extraTokens)
      + 32
    // 각 턴 비용을 한 번만 계산하고 누적합에서 빼며 앞에서 자른다.
    // (이전에는 턴을 하나 버릴 때마다 남은 전체 기록을 다시 셌다 — O(n²).)
    let turnCosts = history.map { estimateTokens($0) }
    var total = turnCosts.reduce(0, +)
    var start = 0
    while start < history.count, fixed + total > budget {
      total -= turnCosts[start]
      start += 1
    }
    return (Array(history[start...]), start)
  }

  /// 자동 정리가 필요한가 — 오래된 턴이 충분히 있고, 예산의 70%를 넘었을 때만.
  public static func shouldCompact(_ conversation: Conversation,
                                   provider: LLMProviderConfig,
                                   keepTurns: Int) -> Bool {
    let boundary = boundaryIndex(turnCount: conversation.turns.count, keepTurns: keepTurns)
    guard boundary >= 2 else { return false }
    let trigger = Int(Double(promptBudget(for: provider)) * triggerRatio)
    return contextTokens(conversation) >= trigger
  }

  // MARK: - 경계·전사·청크

  /// 요약할 턴 수의 경계 — 최근 `keepTurns`개는 원문 유지.
  /// 사용자/어시스턴트 짝이 깨지지 않도록 **짝수**로 맞춘다.
  public static func boundaryIndex(turnCount: Int, keepTurns: Int) -> Int {
    let keep = max(2, keepTurns)
    let raw = max(0, turnCount - keep)
    return raw - (raw % 2)
  }

  /// 요약 입력용 전사 — 역할 라벨 + 첨부 이름 + 출처 URL(최대 2개).
  public static func transcript(_ turns: [Turn], maxCharacters: Int = 200_000) -> String {
    var lines: [String] = []
    var used = 0
    for turn in turns {
      var line = turn.role == .user ? "사용자: " : "어시스턴트: "
      line += turn.text
      if !turn.attachments.isEmpty {
        line += "\n[첨부: " + turn.attachments.map(\.name).joined(separator: ", ") + "]"
      }
      if let sources = turn.sources, !sources.isEmpty {
        line += "\n[출처: " + sources.prefix(2).map(\.url).joined(separator: " | ") + "]"
      }
      if used + line.count > maxCharacters {
        let room = max(0, maxCharacters - used)
        if room > 0 { lines.append(String(line.prefix(room)) + "…") }
        break
      }
      lines.append(line)
      used += line.count + 1
    }
    return lines.joined(separator: "\n")
  }

  /// 긴 전사를 줄 단위로 자른다 — 한 줄이 한도를 넘으면 강제로 나눈다.
  public static func chunks(_ text: String, maxCharacters: Int) -> [String] {
    guard !text.isEmpty else { return [] }
    guard maxCharacters > 0, text.count > maxCharacters else { return [text] }
    var out: [String] = []
    var current = ""
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let s = String(line)
      let separator = current.isEmpty ? 0 : 1
      if current.count + separator + s.count <= maxCharacters {
        if separator == 1 { current += "\n" }
        current += s
        continue
      }
      if !current.isEmpty {
        out.append(current)
        current = ""
      }
      var rest = s
      while rest.count > maxCharacters {
        out.append(String(rest.prefix(maxCharacters)))
        rest = String(rest.dropFirst(maxCharacters))
      }
      current = rest
    }
    if !current.isEmpty { out.append(current) }
    return out
  }

  /// 요약 프롬프트 — 손실을 줄이기 위해 보존/제거 기준을 명시한다.
  public static func summaryPrompt(previous: String?, transcript: String,
                                   maxCharacters: Int) -> String {
    let prev = (previous ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let previousBlock = prev.isEmpty ? "" : """
    기존 요약(새 대화와 합쳐 갱신):
    \(prev)

    """
    return """
    너는 대화 기록을 압축하는 역할이다. 답변하지 말고 요약만 쓴다.
    나중에 이 대화를 이어서 답할 수 있도록 아래를 반드시 보존하라:
    - 사용자의 선호·요청·제약
    - 확정된 결정과 그 이유
    - 사실·수치·날짜·이름·장소·URL
    - 아직 해결되지 않은 질문·할 일
    제거: 인사, 중복, 잡담, 모델의 군더더기.
    한국어로 12줄 이내, \(maxCharacters)자 이내. 원문에 없는 내용을 만들지 말라.

    \(previousBlock)새 대화:
    \(transcript)
    """
  }

  /// 요약 길이 상한 — Apple FM은 4K 예산이라 더 짧게 유지한다.
  public static func summaryLimit(for provider: LLMProviderConfig) -> Int {
    provider.type == .appleFM ? 800 : 4_000
  }

  /// 한 번에 넣을 전사 길이 — Apple FM은 프롬프트·기존 요약·출력까지 합쳐 4K를 넘지 않게.
  public static func chunkLimit(for provider: LLMProviderConfig) -> Int {
    provider.type == .appleFM ? 1_500 : 12_000
  }

  /// 모델이 길게 쓴 요약을 상한에 맞춘다. 빈 요약은 nil.
  public static func clipSummary(_ text: String, maxCharacters: Int) -> String? {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.count > maxCharacters {
      s = String(s.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    return s
  }
}
