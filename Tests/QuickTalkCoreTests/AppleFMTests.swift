import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleFMTests: XCTestCase {
  func testAvailability() throws {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      let a = SystemLanguageModel.default.availability
      print("[TEST] Apple FM availability: \(a)")
      switch a {
      case .available: break
      case .unavailable(let reason):
        throw XCTSkip("Apple FM unavailable: \(reason)")
      }
    } else {
      throw XCTSkip("macOS 26+ 필요")
    }
    #else
    throw XCTSkip("FoundationModels import 불가")
    #endif
  }

  func testRealReply() throws {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      guard case .available = SystemLanguageModel.default.availability else {
        throw XCTSkip("모델 사용 불가")
      }
      let exp = expectation(description: "fm")
      var output = ""
      Task {
        let session = LanguageModelSession(instructions: "한 단어로 답한다.")
        let res = try await session.respond(to: "사과의 색은?")
        output = res.content
        exp.fulfill()
      }
      wait(for: [exp], timeout: 120)
      print("[TEST] Apple FM reply: \(output)")
      XCTAssertFalse(output.isEmpty)
    } else {
      throw XCTSkip("macOS 26+ 필요")
    }
    #else
    throw XCTSkip("FoundationModels import 불가")
    #endif
  }
}
