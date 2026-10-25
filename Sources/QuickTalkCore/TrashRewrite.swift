import Foundation

// [FEATURE] 휴지통 rewrite — `rm` 을 **이동**으로 바꾼다 (PLAN_v0.18 v0.19)
//
// "이 파일 지워줘" 는 되돌릴 수 있어야 한다. 그래서 단순한 `rm` 은 실행하지 않고
// **앱 휴지통으로 옮기는 `mv`** 로 바꿔 실행한다. 잘못 지워도 [되돌리기] 로 되살릴 수 있다.
//
// rewrite 하지 않는 경우(그대로 두고 스냅샷으로만 되돌린다)
//   · 파이프·&&·;·리다이렉션·명령 치환 — 명령의 일부만 바꾸면 의미가 달라진다
//   · 글롭(`*`)·중괄호 확장 — 셸이 실행 시점에 펼쳐 이름이 달라진다
//   · 시스템 전역 경로 — 애초에 쓰기를 열지 않는다
//   · 존재하지 않는 대상(`rm -f`) — `mv` 가 실패해 결과가 달라진다

public struct TrashMove: Equatable {
  public let source: String
  public let destination: String
  public init(source: String, destination: String) {
    self.source = source; self.destination = destination
  }
}

public struct TrashPlan: Equatable {
  /// 실제로 실행할 명령(앱 휴지통으로 이동)
  public let command: String
  /// 이번 이동의 휴지통 폴더
  public let directory: String
  public let moves: [TrashMove]
  public init(command: String, directory: String, moves: [TrashMove]) {
    self.command = command; self.directory = directory; self.moves = moves
  }
}

public enum TrashRewrite {
  /// 단순 `rm` 이면 휴지통 이동으로 바꾼다. 아니면 nil(그대로 실행).
  public static func plan(_ command: String,
                          trashRoot: String,
                          now: Date = Date(),
                          id: String = String(UUID().uuidString.prefix(6)).lowercased()) -> TrashPlan? {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // 복합 명령은 건드리지 않는다.
    let forbidden = ["|", "&", ";", ">", "<", "`", "$(", "\n", "\r"]
    if forbidden.contains(where: { trimmed.contains($0) }) { return nil }

    let words = WriteScope.shellWords(trimmed)
    guard let first = words.first, first == "rm" || first == "/bin/rm" else { return nil }

    var targets: [String] = []
    for word in words.dropFirst() {
      if word.hasPrefix("-") {
        // 대화형(-i)은 입력을 기다려 앱이 멈춘다 — rewrite 하지 않는다.
        if word.contains("i") { return nil }
        continue
      }
      targets.append(word)
    }
    guard !targets.isEmpty else { return nil }

    var sources: [String] = []
    for raw in targets {
      // 글롭·중괄호는 셸이 펼친다 — 이름을 미리 정할 수 없다.
      if raw.contains("*") || raw.contains("?") || raw.contains("[")
          || raw.contains("{") || raw.contains("}") { return nil }
      // 상대 경로는 실제 실행 위치(cwd)를 알 수 없다 — 절대·홈 경로만 바꾼다.
      guard raw.hasPrefix("/") || raw.hasPrefix("~") else { return nil }
      let path = WriteScope.normalize(raw)
      guard !path.isEmpty, path != NSHomeDirectory() else { return nil }
      guard !WriteScope.isSystemPath(path) else { return nil }
      guard FileManager.default.fileExists(atPath: path) else { return nil }
      sources.append(path)
    }

    let stamp = timestamp(now) + "-" + id
    let directory = (trashRoot as NSString).expandingTildeInPath + "/" + stamp
    var moves: [TrashMove] = []
    var parts: [String] = ["mkdir -p \(quote(directory))"]
    for (index, source) in sources.enumerated() {
      let name = String(format: "%03d-%@", index, (source as NSString).lastPathComponent)
      let dest = (directory as NSString).appendingPathComponent(name)
      moves.append(TrashMove(source: source, destination: dest))
      parts.append("mv -f -- \(quote(source)) \(quote(dest))")
    }
    return TrashPlan(command: parts.joined(separator: " && "),
                     directory: directory,
                     moves: moves)
  }

  /// 셸 한 단어 인용 — single quote 로 감싸고 내부 quote 를 이스케이프한다.
  static func quote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func timestamp(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: date)
  }
}
