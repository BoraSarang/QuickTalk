import Foundation

/// 설치된 TTS 목소리 1개(표시·정렬용). AVFoundation 타입과 분리해 두어 테스트한다.
public struct SpeechVoice: Equatable, Identifiable, Hashable {
  public let id: String          // AVSpeechSynthesisVoice.identifier
  public let name: String
  public let language: String    // BCP-47 (ko-KR)
  /// 1 = 기본, 2 = 향상(Enhanced), 3 = 프리미엄(Premium)
  public let quality: Int

  public init(id: String, name: String, language: String, quality: Int) {
    self.id = id
    self.name = name
    self.language = language
    self.quality = quality
  }

  public var qualityLabel: String {
    switch quality {
    case 3: return L("프리미엄")
    case 2: return L("향상")
    case 1: return L("기본")
    default: return L("저품질")
    }
  }

  /// 시스템이 주는 이름이 불친절할 때(예: "음성 2") 식별자로 보정한 이름
  public var friendlyName: String { SpeechCatalog.friendlyName(name: name, id: id) }

  /// "민지(Siri 자연스러운) · 한국어(대한민국) · 향상"
  public var displayName: String {
    "\(friendlyName) · \(SpeechCatalog.languageName(language)) · \(qualityLabel)"
  }
}

/// 음성 언어·목소리 목록을 만드는 순수 함수 모음(설정 창·테스트 공용).
public enum SpeechCatalog {
  /// BCP-47 식별자의 표시 이름 — "ko-KR" → "한국어"
  /// - 표시 언어를 따르게 한다(지역이 미국이어도 한국어 UI면 "한국어(대한민국)").
  /// - Parameter locale: 테스트·특수 용도에서 직접 지정.
  public static func languageName(_ identifier: String, locale: Locale? = nil) -> String {
    let loc = locale ?? Locale(identifier: L10n.effective == .ko ? "ko_KR" : "en_US")
    guard !identifier.isEmpty else { return L("시스템 기본") }
    if let name = loc.localizedString(forIdentifier: identifier) { return name }
    return identifier
  }

  /// 언어에 맞는 목소리만 골라 **품질 높은 순 → 이름 순**으로 정렬한다.
  /// - Parameter language: "ko-KR" · "en" · ""(전체).
  ///   지역까지 지정했으면(예: "en-US") 그 지역 목소리를 우선하고, 하나도 없으면 주 언어("en")로 넓힌다.
  public static func voices(matching language: String, from all: [SpeechVoice]) -> [SpeechVoice] {
    let primary = language.split(separator: "-").first.map { String($0).lowercased() } ?? ""
    let normalized = language.lowercased()
    let exact = all.filter { $0.language.lowercased() == normalized }
    let filtered: [SpeechVoice]
    if !exact.isEmpty {
      filtered = exact
    } else if !primary.isEmpty {
      filtered = all.filter { $0.language.lowercased().hasPrefix(primary) }
    } else {
      filtered = all
    }
    let sorted = filtered.sorted {
      if $0.quality != $1.quality { return $0.quality > $1.quality }
      let byName = $0.name.localizedStandardCompare($1.name)
      if byName != .orderedSame { return byName == .orderedAscending }
      return $0.id < $1.id
    }
    return deduplicated(sorted)     // 품질 순으로 정렬한 뒤라 같은 이름이면 좋은 쪽이 남는다
  }

  /// 같은 목소리의 다른 포장(예: compact / super-compact)은 **높은 품질 하나만** 남긴다.
  /// (macOS는 한국어 Yuna를 compact·super-compact 두 벌로 주는데 목록에 똑같이 두 번 보이면 고를 수 없다)
  public static func deduplicated(_ voices: [SpeechVoice]) -> [SpeechVoice] {
    var seen = Set<String>()
    var out: [SpeechVoice] = []
    for v in voices {
      let key = "\(v.name.lowercased())|\(v.language.lowercased())"
      if seen.contains(key) { continue }
      seen.insert(key)
      out.append(v)
    }
    return out
  }

  /// 표시 이름 보정 — "음성 2"(Siri 자연스러운 목소리)처럼 알아보기 어려운 이름을 풀어 쓴다.
  public static func friendlyName(name: String, id: String) -> String {
    guard id.contains("siri.natural") else { return name }
    let tail = id.split(separator: ".").last.map(String.init) ?? ""
    return tail.isEmpty ? "\(name) (Siri 자연스러운)" : "Siri 자연스러운 (\(tail))"
  }

  /// 목소리 목록에 없는 언어까지 포함한 **사용 가능한 언어**(중복 제거·정렬).
  public static func languages(from all: [SpeechVoice]) -> [String] {
    Array(Set(all.map { $0.language })).sorted {
      languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
    }
  }
}
