// 스파이크 1 — Apple FM(FoundationModels) tool calling 루프 검증
// 2026-10-21 · PLAN_v0.18 §5
//
// 검증 목표
//   1) LanguageModelSession에 Tool을 넘길 수 있는가
//   2) 모델이 실제로 tool_calls 를 만드는가
//   3) 도구 결과를 transcript 에 되돌려 최종 답을 받을 수 있는가
//
// 실행: swiftc -O -o /tmp/spike-applefm spike-applefm-tools.swift && /tmp/spike-applefm

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 도구 정의 (FoundationModels 는 @Tool 매크로가 없으므로 Tool 프로토콜을 직접 구현)

@Generable
struct EchoArgs {
    @Guide(description: "사용자에게 그대로 되돌려줄 문자열")
    var message: String
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct EchoTool: Tool {
    let name = "echo"
    let description = "주어진 메시지를 그대로 되돌려준다. 사용자가 'A+B' 를 물으면 A+B 를 인자로 전달한다."

    func call(arguments: EchoArgs) async throws -> String {
        print("[SPIKE] ✅ Tool.call(arguments:) 실행됨 — message=\(arguments.message)")
        return "ECHO::\(arguments.message)"
    }
}
#endif

// MARK: - 실행

@main
struct Spike {
    static func main() async {
        do {
            try await run()
        } catch {
            print("[SPIKE] FAIL — 오류: \(error)")
        }
    }

    static func run() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            print("[SPIKE] FAIL — macOS 26 미만")
            return
        }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            print("[SPIKE] Apple FM 사용 가능")
        case .unavailable(let reason):
            print("[SPIKE] FAIL — Apple FM 사용 불가: \(reason)")
            print("[SPIKE] (Apple Intelligence 활성화/언어 지원 필요)")
            return
        }

        let tool = EchoTool()
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "간결한 한국어 어시스턴트. 계산이나 되돌리기 요청은 echo 도구를 쓸 수 있다."
        )
        print("[SPIKE] 세션 생성 완료 (tools: [echo])")

        // ── 1차 응답: 도구 호출이 만들어지는지 ──
        let first = try await session.respond(to: "echo 도구를 써서 'QUICKTALK-OK' 를 한 번 되돌려줘.")
        print("[SPIKE] 1차 응답 content=\(first.content)")

        var callCount = 0
        for entry in first.transcriptEntries {
            guard case .toolCalls(let calls) = entry else { continue }
            for call in calls {
                callCount += 1
                print("[SPIKE] tool_call #\(callCount): name=\(call.toolName) id=\(call.id)")

                // GeneratedContent → 인자 추출
                var message = ""
                if case .structure(let props, _) = call.arguments.kind,
                   let v = props["message"], case .string(let s) = v.kind {
                    message = s
                } else {
                    print("[SPIKE] ⚠️ 인자 형식 예상 밖: \(call.arguments.kind)")
                }
                print("[SPIKE] 인자 message=\(message)")

                // 도구 실행 → 결과를 transcript 에 되돌린다
                let result = try await tool.call(arguments: EchoArgs(message: message))
                session.transcript.append(.toolOutput(
                    Transcript.ToolOutput(id: call.id,
                                          toolName: call.toolName,
                                          segments: [.text(Transcript.TextSegment(content: result))])
                ))
                print("[SPIKE] tool_output 추가됨: \(result)")
            }
        }

        if callCount == 0 {
            print("[SPIKE] FAIL — tool_calls 가 만들어지지 않음 (모델이 도구를 선택하지 않음)")
            return
        }

        // ── 2차 응답: 도구 결과를 받아 최종 답 ──
        let final = try await session.respond(to: "방금 도구에서 받은 결과를 한 문장으로 알려줘.")
        print("[SPIKE] ✅ 최종 답변: \(final.content)")
        print("[SPIKE] RESULT=PASS")
        #else
        print("[SPIKE] FAIL — FoundationModels 없음")
        #endif
    }
}