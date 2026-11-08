import XCTest
@testable import QuickTalkCore

final class ModelCatalogTests: XCTestCase {
  private let registryJSON = """
  {
    "opencode": {
      "models": {
        "deepseek-v4.1-flash-free": {
          "name": "DeepSeek V4.1 Flash Free",
          "tool_call": true,
          "reasoning": true,
          "attachment": true,
          "limit": {"context": 200000, "output": 32000},
          "modalities": {"input": ["text", "image"], "output": ["text"]},
          "reasoning_options": [{"type": "effort", "values": ["low", "high", "max"]}],
          "cost": {"input": 0, "output": 0}
        },
        "big-pickle": {
          "name": "Big Pickle",
          "tool_call": true,
          "reasoning": true,
          "attachment": false,
          "limit": {"context": 200000, "output": 32000},
          "modalities": {"input": ["text"]},
          "reasoning_options": []
        }
      }
    },
    "other": {
      "models": {
        "deepseek-v4.1-flash-free": {
          "name": "DeepSeek Mirror",
          "limit": {"context": 1000}
        }
      }
    }
  }
  """

  private func registry() throws -> ModelsDevRegistry {
    try ModelsDevRegistry(data: Data(registryJSON.utf8))
  }

  func testParsesModelsDevFields() throws {
    let reg = try registry()
    let info = try XCTUnwrap(reg.index["deepseek-v4.1-flash-free"])
    XCTAssertEqual(info.name, "DeepSeek V4.1 Flash Free")
    XCTAssertEqual(info.context, 200_000)
    XCTAssertEqual(info.output, 32_000)
    XCTAssertEqual(info.input, ["text", "image"])
    XCTAssertTrue(info.toolCall)
    XCTAssertTrue(info.reasoning)
    XCTAssertTrue(info.attachment)
    XCTAssertEqual(info.effort, ["low", "high", "max"])
    XCTAssertEqual(info.source, "opencode")
    XCTAssertTrue(info.looksFree)
  }

  func testPrefersProviderWithMoreDetail() throws {
    let reg = try registry()
    // `other`가 나중에 나오지만 정보가 적으므로 opencode 항목이 남는다.
    let info = try XCTUnwrap(reg.index["deepseek-v4.1-flash-free"])
    XCTAssertEqual(info.context, 200_000)
    XCTAssertEqual(info.source, "opencode")
  }

  func testMergePreservesServerOrderAndFallsBack() throws {
    let reg = try registry()
    let ids = ["big-pickle", "unknown-model", "deepseek-v4.1-flash-free"]
    let merged = ModelCatalog.merge(ids: ids, registry: reg)
    XCTAssertEqual(merged.map(\.id), ids)
    XCTAssertEqual(merged[0].name, "Big Pickle")
    XCTAssertFalse(merged[1].hasDetails)
    XCTAssertEqual(merged[1].name, "unknown-model")
    XCTAssertEqual(merged[2].name, "DeepSeek V4.1 Flash Free")
  }

  func testMergePreviousKeepsKnownDetailsWhenRegistryFails() {
    let previous = ModelCatalogEntry(providerID: "p", baseURL: "http://x",
                                     fetchedAt: Date(),
                                     models: [ModelInfo(id: "a", name: "A", context: 8_000)])
    let merged = ModelCatalog.merge(ids: ["a", "b"], previous: previous)
    XCTAssertEqual(merged[0].context, 8_000)
    XCTAssertEqual(merged[1].name, "b")
  }

  func testCacheRoundTripAndTTL() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("model-catalog-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let fresh = ModelCatalogEntry(providerID: "p", baseURL: "http://x",
                                  fetchedAt: Date(), models: [ModelInfo(id: "a")])
    let stale = ModelCatalogEntry(providerID: "q", baseURL: "http://y",
                                  fetchedAt: Date().addingTimeInterval(-ModelCatalog.ttl - 1),
                                  models: [ModelInfo(id: "b")])
    try ModelCatalog.save(["p": fresh, "q": stale], to: url)
    let loaded = ModelCatalog.load(from: url)
    XCTAssertEqual(loaded["p"]?.models.first?.id, "a")
    XCTAssertTrue(try XCTUnwrap(loaded["p"]).isFresh())
    XCTAssertFalse(try XCTUnwrap(loaded["q"]).isFresh())
  }

  func testInvalidRegistryThrows() {
    XCTAssertThrowsError(try ModelsDevRegistry(data: Data("[]".utf8)))
  }

  func testAttachmentInferredFromModalities() throws {
    let json = """
    {"p":{"models":{"img":{"name":"Img","modalities":{"input":["text","image"]}},
                        "plain":{"name":"Plain","modalities":{"input":["text"]}}}}}
    """
    let reg = try ModelsDevRegistry(data: Data(json.utf8))
    XCTAssertTrue(try XCTUnwrap(reg.index["img"]).attachment)
    XCTAssertFalse(try XCTUnwrap(reg.index["plain"]).attachment)
  }
}
