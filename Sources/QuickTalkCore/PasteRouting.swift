import Foundation

/// 클립보드의 URL 을 **첨부 파일**과 **일반 텍스트**로 나누는 순수 규칙.
///
/// 브라우저 주소창에서 복사하면 클립보드에 `public.url` 이 함께 들어가고,
/// `NSPasteboard.readObjects(forClasses: [NSURL.self])` 가 그 **웹 주소**를 돌려준다.
/// 예전에는 이를 파일로 오인해 `9zOwUT1PdKY` 같은 확장자 없는 "파일"로 판정하고
/// 지원하지 않는 형식 안내만 띄운 뒤 **붙여넣기를 삼켰다** — URL 을 입력창에 넣을 수 없었다.
public enum PasteRouting {
  /// 파일로 취급할 URL 만 고른다 — `file://` 이 아닌 웹 주소는 기본 텍스트 붙여넣기로 남긴다.
  public static func fileURLs(from urls: [URL]) -> [URL] {
    urls.filter { $0.isFileURL }
  }
}
