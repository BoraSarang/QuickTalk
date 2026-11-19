import Foundation

// [FEATURE] 지난 작업 조회 (v0.41.2)
//
// 배경(2026-11-19): "지난 주에 어디까지 했지?"에 답하려고 모델이 `history.json` 을
// 셸로 8번 읽었다. 앱 데이터 보호(AppDataGuard)가 매 읽기마다 승인 카드를 띄워
// 사용자가 [한 번 허용]을 8번 눌러야 했다.
//
// 해결: 대화 제목·마지막 질문·Job 결과만 모은 **압축 요약**을 한 번에 돌려준다.
// 원문 전체를 넘기지 않고, 현재 대화는 뺀다. 모델은 이 요약만으로 답한다.
public enum PastWork {
  public static let defaultDays = 7
  public static let maximumDays = 60
  /// 모델에게 돌려주는 요약의 상한 — `AgentRunner.summarize` 가 2,000자에서 자르므로 그보다 작게.
  public static let maximumCharacters = 1_800
  public static let maximumConversations = 8
  public static let maximumJobs = 5

  /// 지난 기록을 한 블록으로 만든다.
  ///
  /// - Parameters:
  ///   - conversations: 전체 대화 기록(보관함). 현재 대화는 `excluding` 로 뺀다.
  ///   - jobs: 맡긴 작업 목록.
  ///   - days: 며칠 전까지 볼지(1~60).
  ///   - query: 제목·질문·결과에서 찾을 말(비어 있으면 전부).
  ///   - conversationID: 지금 대화의 ID — 자기 자신을 참고하지 않게 뺀다.
  public static func digest(conversations: [Conversation],
                            jobs: [Job],
                            days: Int = defaultDays,
                            query: String = "",
                            excluding conversationID: UUID? = nil,
                            now: Date = Date()) -> String {
    let span = max(1, min(days, maximumDays))
    let since = now.addingTimeInterval(-Double(span) * 86_400)
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let english = L10n.effective == .en

    let jobLines = jobRows(jobs, since: since, needle: needle, english: english)
    let conversationLines = conversationRows(conversations, since: since, needle: needle,
                                             excluding: conversationID, english: english)

    guard !jobLines.isEmpty || !conversationLines.isEmpty else {
      return english
        ? "No conversations or jobs were left in the last \(span) days."
        : "지난 \(span)일 동안 남은 작업·대화 기록이 없습니다."
    }

    var out = english
      ? "[Past \(span) days — compact digest, not full transcripts]\n"
      : "[지난 \(span)일 기록 — 참고용 요약. 원문 전체가 아니다]\n"

    if !jobLines.isEmpty {
      out += english ? "\n## Jobs\n" : "\n## 완료·진행한 작업\n"
      out += jobLines.joined(separator: "\n") + "\n"
    }

    if !conversationLines.isEmpty {
      out += english ? "\n## Conversations\n" : "\n## 대화\n"
      var used = out.count
      var included = 0
      var skipped = 0
      for line in conversationLines {
        guard included < maximumConversations,
              used + line.count + 1 <= maximumCharacters else {
          skipped += 1
          continue
        }
        out += line + "\n"
        used += line.count + 1
        included += 1
      }
      if skipped > 0 {
        out += english ? "- …and \(skipped) more\n" : "- …외 \(skipped)개\n"
      }
    }

    out += english
      ? "\n— Summarize only what the user asked; do not copy transcripts."
      : "\n— 사용자가 물은 범위만 요약하고, 원문을 그대로 옮기지 않는다."
    return out
  }

  // MARK: - 행 만들기

  private static func jobRows(_ jobs: [Job], since: Date, needle: String,
                              english: Bool) -> [String] {
    let rows = jobs
      .filter { job in
        // 대기 중인 작업은 아직 "한 일"이 아니다.
        guard job.status != .queued else { return false }
        guard (job.finishedAt ?? job.updatedAt) >= since else { return false }
        guard !needle.isEmpty else { return true }
        let haystack = [job.title, job.goal, job.resultSummary ?? "", job.workspacePath]
          .joined(separator: " ")
          .lowercased()
        return haystack.contains(needle)
      }
      .sorted { ($0.finishedAt ?? $0.updatedAt) > ($1.finishedAt ?? $1.updatedAt) }
      .prefix(maximumJobs)

    return rows.map { job in
      let date = dateText(job.finishedAt ?? job.updatedAt)
      let status = statusText(job.status, english: english)
      var line = "- \(date) · \(status) · \(oneLine(job.title, limit: 60))"
      if let summary = resultLine(job.resultSummary) {
        line += " — \(summary)"
      }
      if !job.artifactPaths.isEmpty {
        line += english ? " · \(job.artifactPaths.count) files"
                        : " · 파일 \(job.artifactPaths.count)개"
      }
      return line
    }
  }

  /// 결과 요약 한 줄. `JobService` 가 **계획 제안 문구**를 결과 요약으로 남긴 기록이 있어
  /// (2026-11-15 볼륨 Job) 그대로 쓰면 "계획을 제안했습니다"가 결과처럼 보인다 — 뺀다.
  static func resultLine(_ summary: String?) -> String? {
    let line = oneLine(summary ?? "", limit: 120)
    guard !line.isEmpty else { return nil }
    if line.contains("계획을 제안했습니다") || line.contains("[실행]을 누르면") { return nil }
    return line
  }

  private static func conversationRows(_ conversations: [Conversation], since: Date,
                                       needle: String, excluding conversationID: UUID?,
                                       english: Bool) -> [String] {
    let rows: [(Date, String)] = conversations.compactMap { conversation in
      guard conversation.id != conversationID else { return nil }
      let turns = conversation.turns.filter {
        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      guard !turns.isEmpty else { return nil }

      let turnDates = turns.compactMap(\.createdAt)
      let lastActivity = max(turnDates.max() ?? conversation.updatedAt, conversation.updatedAt)
      guard lastActivity >= since else { return nil }

      if !needle.isEmpty {
        let haystack = ([conversation.displayTitle] + turns.map(\.text))
          .joined(separator: " ")
          .lowercased()
        guard haystack.contains(needle) else { return nil }
      }

      let title = oneLine(conversation.displayTitle, limit: 50)
      let question = turns.last(where: { $0.role == .user })
        .map { oneLine($0.text, limit: 70) } ?? ""
      let answer = turns.last(where: { $0.role == .assistant })
        .map { oneLine($0.text, limit: 80) }
        .flatMap { isBoilerplateAnswer($0) ? nil : $0 } ?? ""

      var line = "- \(dateText(lastActivity)) · \(title)"
      if !question.isEmpty { line += (english ? " — asked: " : " — 질문: ") + "\"\(question)\"" }
      if !answer.isEmpty { line += (english ? " → answered: " : " → 답: ") + answer }
      return (lastActivity, line)
    }
    return rows.sorted { $0.0 > $1.0 }.map(\.1)
  }

  /// "응답을 중지했습니다" 같은 중단·오류 문구는 답이 아니다 — '어디까지 했는지'를 흐린다.
  static func isBoilerplateAnswer(_ text: String) -> Bool {
    let lowered = text.lowercased()
    let phrases = ["응답을 중지했습니다", "응답이 중지되었습니다",
                   "도구 실행은 끝났지만 모델이 최종 답변을 작성하지 못했습니다",
                   "the response was stopped", "response stopped"]
    return phrases.contains { lowered.contains($0) }
  }

  // MARK: - 글자 다듬기

  /// 첫 줄만, 공백을 하나로, 길면 자른다. 요약이 여러 줄이면 첫 줄이 가장 뜻이 크다.
  static func oneLine(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let first = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty } ?? ""
    let collapsed = first
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit - 1)) + "…"
  }

  private static func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM/dd"
    return formatter.string(from: date)
  }

  private static func statusText(_ status: Job.Status, english: Bool) -> String {
    if english {
      switch status {
      case .running: return "running"
      case .queued: return "queued"
      case .waitingApproval: return "waiting"
      case .paused: return "paused"
      case .completed: return "done"
      case .failed: return "failed"
      case .cancelled, .interrupted: return "stopped"
      }
    }
    switch status {
    case .running: return "진행 중"
    case .queued: return "대기 중"
    case .waitingApproval: return "승인 대기"
    case .paused: return "일시 중지"
    case .completed: return "완료"
    case .failed: return "실패"
    case .cancelled, .interrupted: return "중단"
    }
  }
}
