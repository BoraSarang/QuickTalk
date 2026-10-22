import Foundation

// [FEATURE] 실행 감사 기록 (PLAN_v0.18 §7)
//
// 무엇이 언제 실행됐는지 남긴다. **명령 전문에 붙은 비밀은 가린다**(토큰·키·비밀번호).
// 출력 본문은 남기지 않는다(내용이 아니라 사실만).

/// 감사 기록 1건 — JSON 한 줄을 필드로 나눈 것.
/// (설정 화면이 이 구조로 그린다 — 원문 JSON은 `raw` 에 남는다)
struct AgentAuditEntry: Identifiable {
  let id: Int
  let date: Date?
  let command: String
  /// 읽기/쓰기/실행 (`AgentPermissionLevel.rawValue`)
  let level: String
  /// 위험도 (`AgentRiskLevel.rawValue`)
  let risk: Int
  /// 허용/거부
  let decision: String
  let exitCode: Int
  let elapsedMs: Int
  /// 원문 JSON 한 줄 (툴팁용)
  let raw: String

  var allowed: Bool { decision == "allow" }
  var levelName: String { AgentPermissionLevel(rawValue: level)?.displayName ?? level }
  var riskName: String? {
    guard let risk = AgentRiskLevel(rawValue: risk), risk != .normal else { return nil }
    return risk.displayName
  }
}

enum AgentAudit {
  /// 기록 파일 — `~/Library/Application Support/QuickTalk/agent-audit.log` (한 줄 = 한 건)
  static var logURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("QuickTalk/agent-audit.log")
  }

  /// 실행 1건을 기록한다.
  static func record(command: String,
                     level: AgentPermissionLevel,
                     risk: AgentRiskLevel,
                     decision: String,
                     exitCode: Int32?,
                     elapsedMs: Int) {
    let entry: [String: Any] = [
      "at": ISO8601DateFormatter().string(from: Date()),
      "cmd": mask(command),
      "level": level.rawValue,
      "risk": String(risk.rawValue),
      "decision": decision,
      "exit": exitCode ?? -1,
      "ms": elapsedMs
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: entry),
          let line = String(data: data, encoding: .utf8) else { return }
    let url = logURL
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(Data((line + "\n").utf8))
      try? handle.close()
    } else {
      try? Data((line + "\n").utf8).write(to: url)
    }
  }

  /// 최근 기록을 읽는다(설정 화면용). newest first.
  ///
  /// 예전에는 JSON 한 줄을 그대로 보여 줘서 읽을 수 없었다(2026-10-22 사용자 지적:
  /// "실행 기록 보기.. 어떻게 보라는 건지"). 이제 필드로 나눠 돌려주고 화면이 읽기 쉽게 그린다.
  static func recentEntries(limit: Int = 30) -> [AgentAuditEntry] {
    guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
    let iso = ISO8601DateFormatter()
    var entries: [AgentAuditEntry] = []
    let lines = text.split(separator: "\n").suffix(limit).reversed()
    for (index, line) in lines.enumerated() {
      let raw = String(line)
      guard let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      entries.append(AgentAuditEntry(
        id: index,
        date: (object["at"] as? String).flatMap { iso.date(from: $0) },
        command: object["cmd"] as? String ?? "",
        level: object["level"] as? String ?? "",
        risk: Int((object["risk"] as? String) ?? "") ?? (object["risk"] as? Int ?? 0),
        decision: object["decision"] as? String ?? "",
        exitCode: object["exit"] as? Int ?? -1,
        elapsedMs: object["ms"] as? Int ?? 0,
        raw: raw
      ))
    }
    return entries
  }

  /// 기록을 지운다.
  static func clear() {
    try? FileManager.default.removeItem(at: logURL)
  }

  /// 비밀 가리기 — 토큰·키·비밀번호가 명령에 붙어 있으면 가린다([HARD] 로그 마스킹).
  static func mask(_ command: String) -> String {
    var text = command
    let patterns = [
      #"(?i)(token|api[_-]?key|apikey|password|passwd|secret)(\s*[=:]\s*)\S+"#,
      #"(?i)(authorization:\s*bearer\s+)\S+"#,
      #"(?i)(-p\s+)\S{6,}"#
    ]
    for p in patterns {
      guard let re = try? NSRegularExpression(pattern: p) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      text = re.stringByReplacingMatches(in: text, range: range,
                                         withTemplate: "$1$2***")
    }
    if text.count > 300 { text = String(text.prefix(300)) + "…" }
    return text
  }
}
