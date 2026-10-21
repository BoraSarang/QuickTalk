import Foundation

/// 표시 언어 — **시스템 기본**이면 macOS 선호 언어를 따른다(한국어가 아니면 English).
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Equatable {
  case system, korean, english

  public var id: String { rawValue }

  /// 설정 화면에 보이는 이름(각 언어로 표기)
  public var displayName: String {
    switch self {
    case .system: return L("시스템 기본")
    case .korean: return "한국어"
    case .english: return "English"
    }
  }
}

/// 화면 테마 — 시스템/라이트/다크
public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Equatable {
  case system, light, dark

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .system: return L("시스템")
    case .light: return L("라이트")
    case .dark: return L("다크")
    }
  }
}

/// 한국어 원문을 키로 쓰는 런타임 번역표.
/// - 뷰는 `L("설정")`처럼 감싸기만 하면 되고, 번역이 없으면 **한국어로 폴백**한다.
/// - `L10n.language`는 설정이 바뀔 때 앱이 갱신한다(설정 변경 → UIStore 발행 → 뷰 재평가).
public enum L10n {
  public enum Effective: String { case ko, en }

  /// 설정값(시스템/한국어/영어)
  public static var language: AppLanguage = .system

  /// 실제 적용 언어 — 시스템 기본이면 선호 언어의 첫 항목을 본다.
  public static var effective: Effective {
    switch language {
    case .korean: return .ko
    case .english: return .en
    case .system:
      let code = Locale.preferredLanguages.first ?? "en"
      return code.hasPrefix("ko") ? .ko : .en
    }
  }

  /// 한국어 원문 → 현재 언어 문구(없으면 원문)
  public static func t(_ ko: String) -> String {
    guard effective == .en else { return ko }
    return table[ko] ?? ko
  }

  /// 보간 문구용 — 키에 `%d`·`%@` 같은 포맷을 쓰고 인자를 넘긴다.
  /// 예: `Lf("%d턴 · %@", count, date)`
  public static func f(_ template: String, _ args: CVarArg...) -> String {
    String(format: t(template), arguments: args)
  }

  // MARK: - 포맷 헬퍼(자주 쓰는 것)

  /// "3턴" / "3 turns"
  public static func turns(_ n: Int) -> String { f("%d턴", n) }

  /// "3개" / "3 items"
  public static func count(_ n: Int) -> String { f("%d개", n) }

  /// "30일" / "30 days"
  public static func days(_ n: Int) -> String { f("%d일", n) }

  /// "1분 12초" / "1m 12s"
  public static func duration(ms: Int) -> String {
    let seconds = Double(ms) / 1000
    if seconds < 60 { return f("%.1f초", seconds) }
    let total = Int(seconds.rounded())
    return f("%d분 %d초", total / 60, total % 60)
  }
}

/// 짧은 래퍼 — 뷰 코드에서 `Text(L("설정"))`처럼 쓴다.
public func L(_ ko: String) -> String { L10n.t(ko) }

/// 보간 문구 — `Lf("%d턴", n)`
public func Lf(_ template: String, _ args: CVarArg...) -> String { L10n.f(template, args) }
