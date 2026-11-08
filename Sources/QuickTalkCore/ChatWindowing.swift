import Foundation

// 대화 윈도잉(v0.35.3) — **화면에 그리지 않는 순수 계산**만 둔다.
//
// 긴 대화를 열 때 모든 턴을 그리면 마크다운 레이아웃이 글자 수에 거의 선형으로 비싸진다
// (실측 ≈53~76µs/자 — 34턴/33,424자에서 2.6초 이상). 그래서 최근 턴부터 글자 예산만큼만
// 그리고, 더 오래된 턴은 "이전 대화 더 보기"로 필요할 때 펼친다.
//
// LazyVStack 대신 VStack 을 쓰는 이유: LazyVStack 은 아직 만들지 않은 행의 높이를 **추정**해서
// 문서 끝으로 핀하면 실제 내용 뒤의 빈 꼬리에 착지했다(400폭 추정 8,233pt vs 실제 7,665pt).
// VStack 은 높이가 정확해 바닥 고정이 어긋나지 않는다.

public enum ChatWindowing {
  /// 처음 그리는 최근 턴의 글자 예산. 400폭에서 레이아웃 ~0.3초 수준.
  public static let baseCharBudget = 6_000
  /// "이전 대화 더 보기" 한 번에 추가하는 글자 예산.
  public static let step = 6_000
  /// 대화가 아주 짧아도 질문+답변 두 턴은 항상 보여 준다.
  public static let minimumTurns = 2

  /// 그릴 첫 턴의 인덱스 — 최근 턴부터 `budget` 글자까지 거슬러 올라간다.
  ///
  /// - Parameters:
  ///   - charCounts: 턴별 글자 수(질문·답변·도구 출력 포함).
  ///   - budget: 그릴 글자 예산. `.max` 면 전부 그린다.
  ///   - minimumTurns: 예산과 무관하게 항상 보여 줄 최근 턴 수.
  /// - Returns: 처음 그릴 턴의 인덱스(0 이면 전부).
  public static func startIndex(charCounts: [Int], budget: Int,
                                minimumTurns: Int = minimumTurns) -> Int {
    let minimum = max(0, minimumTurns)
    guard minimum > 0, charCounts.count > minimum else { return 0 }
    var start = charCounts.count - minimum
    var chars = charCounts[start...].reduce(0, +)
    while start > 0 {
      let size = charCounts[start - 1]
      // 넘침 방지 — `chars + size` 대신 뺄셈으로 비교한다.
      if size > budget - chars { break }
      chars += size
      start -= 1
    }
    return start
  }
}
