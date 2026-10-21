import Foundation

// [FEATURE] 도구 카탈로그 + 에이전트 지시문 (PLAN_v0.18 §6)
//
// 도구는 **5개의 손**뿐이다. "무엇을 할지"는 모델이 정한다.
// (`disk_usage`·`calendar_list` 같은 도구를 늘려가는 방식은 천장이 있다 — pip·uv·npx·cargo…
//  어떤 이름이 들어올지 예측할 수 없다. 그 대신 `shell` 하나로 다 처리한다.)

public enum AgentToolCatalog {
  /// 셸 명령 실행 — 앱이 실행하는 손
  public static let shell = AgentTool(
    name: "shell",
    description: """
      Run a command in the macOS shell and return its output. \
      Use this to inspect the machine (disk, processes, network, files) and to run tools \
      (brew, adb, npm, python, …). Commands run under a sandbox: a read-only attempt runs first, \
      and if the command needs write or network access the app asks the user first. \
      Do not run destructive commands (rm -rf /, mkfs, …).
      """,
    parameters: [
      "type": "object",
      "properties": [
        "command": [
          "type": "string",
          "description": "The shell command to run. Use plain, widely available commands."
        ]
      ],
      "required": ["command"]
    ])

  /// 파일 읽기 — 셸 없이 안전하게 읽는다
  public static let readFile = AgentTool(
    name: "read_file",
    description: """
      Read a UTF-8 text file and return its contents. Use it for source files, config files and \
      logs. Binary files are not supported — use the shell for those.
      """,
    parameters: [
      "type": "object",
      "properties": [
        "path": ["type": "string", "description": "Absolute path of the file to read."],
        "max_bytes": ["type": "integer", "description": "Maximum bytes to read (default 20000)."]
      ],
      "required": ["path"]
    ])

  /// 디렉터리 목록
  public static let listDir = AgentTool(
    name: "list_dir",
    description: """
      List the entries of a directory (name, type, size). Use it to explore folders before reading.
      """,
    parameters: [
      "type": "object",
      "properties": [
        "path": ["type": "string", "description": "Absolute path of the directory to list."]
      ],
      "required": ["path"]
    ])

  public static let all: [AgentTool] = [shell, readFile, listDir]

  /// 이름으로 도구를 찾는다.
  public static func tool(named name: String) -> AgentTool? {
    all.first { $0.name == name }
  }
}

// MARK: - 에이전트 지시문

public enum AgentInstructions {
  /// 도구 사용 규칙 — 모델에게 주는 최소 지시.
  /// 앱이 무엇을 할 수 있는지는 **모델이 이미 아는 macOS 지식**으로 판단한다(앱은 이름을 모른다).
  public static let text = """
    너는 macOS에서 동작하는 도우미다. 사용자의 질문을 **직접 조사해서** 답해야 한다. \
    추측으로 답하지 말고 필요한 명령을 실행해 확인한 뒤 답한다.

    도구 사용 규칙
    - 상태를 확인하는 명령(ls, df, ps, top, sw_vers, system_profiler, brew list, adb devices 등)은 \
    바로 실행해도 된다.
    - 명령을 정확히 모르면 먼저 `--help` 또는 `man`으로 확인한다. 지식이 낡았을 수 있다.
    - 시스템에 영향을 주는 명령(설치, 삭제, 설정 변경)은 앱이 사용자에게 먼저 확인한다. \
    확인을 받으면 범위가 그 자리에서만 허용된다.
    - 파괴적인 명령(rm -rf /, mkfs, dd 등)은 실행하지 않는다.
    - 한 번에 하나의 명령을 실행하고, 결과를 보고 다음을 정한다.

    답할 때
    - 실행한 결과를 그대로 요약하지 말고, **사용자에게 필요한 정보**를 중심으로 말한다.
    - 도구를 실행했다면 **그 결과의 숫자·사실로 답한다.** 결과를 쓰지 않으면 다시 확인한다.
    - 숫자는 단위와 함께 적는다(예: 521 GiB 남음, 2.25 Mbps).
    - 확인이 필요하면 왜 필요한지 한 줄로 밝힌다.
    """

  /// 앱 자신에 대한 지식 — 모델이 자기 앱과 겹치는 일을 하지 않도록 주입한다.
  public static func selfKnowledge(settings: QuickTalkSettings) -> String {
    let home = NSHomeDirectory()
    var lines: [String] = []
    lines.append("이것은 QuickTalk 이라는 macOS 메뉴바 앱이다. 사용자가 지금 이 앱으로 묻고 있다.")
    lines.append("- 저장 위치: ~/Library/Application Support/QuickTalk (기록 history.json · 공통 메모리 memory.json)")
    lines.append("- 앱 지원 폴더: \(home)/Library/Application Support/QuickTalk")
    lines.append("- 설정: \(home)/Library/Application Support/QuickTalk/settings.json (UserDefaults 아님)")
    lines.append("- 음성 입력 백엔드: whisper.cpp(whisper-cli + ggml-*.bin) · mlx-whisper(MLX) · Apple 받아쓰기")
    lines.append("- 음성 출력: Apple TTS · Edge TTS · Piper")
    if let p = settings.activeProvider {
      lines.append("- 지금 쓰는 AI: \(p.displayName) (모델 \(p.model))")
    }
    lines.append("- 앱 안에서 이미 하는 일: 웹 검색(Exa) · 공통 메모리 · 대화 요약 자동 정리 · QuickShelf(클립보드/파일/캡처)")
    lines.append("- 앱에 이미 있는 기능은 다시 설치하거나 만들지 말고, 설정 경로만 안내한다.")
    return lines.joined(separator: "\n")
  }
}
