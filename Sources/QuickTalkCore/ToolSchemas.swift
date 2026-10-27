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
        ],
        "purpose": [
          "type": "string",
          "description": "One short line in the user's language saying why this command is needed. Shown on the execution card so the user can judge the command at a glance."
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

  /// 프로세스 사용량 — `ps`·`top` 은 setuid 라 샌드박스가 실행을 막는다. 앱이 직접 읽는다.
  public static let processes = AgentTool(
    name: "processes",
    description: """
      Read CPU and memory usage of running processes. This is the **only** way to see per-process \
      usage here: ps and top are setuid binaries and the sandbox refuses to execute them \
      ("Operation not permitted"), no matter what permission is granted. \
      Samples twice over a short window and returns the top processes.
      """,
    parameters: [
      "type": "object",
      "properties": [
        "sort": ["type": "string", "enum": ["cpu", "memory"],
                 "description": "Sort key (default: cpu)."],
        "limit": ["type": "integer",
                  "description": "How many processes to return (default 5, max 30)."]
      ],
      "required": []
    ])

  /// 스크린샷 — 창/화면을 찍어 다음 판단에 이미지로 붙인다(v0.21).
  public static let screenshot = AgentTool(
    name: "screenshot",
    description: """
      Capture the screen or the frontmost window as an image and look at it in the next step. \
      Use it when the answer depends on what is **visually** on screen (a chart, an error dialog, \
      a layout, a game, a video frame). Text-heavy windows are better read with shell/read_file. \
      Requires Screen Recording permission; if it is missing the tool explains how to allow it. \
      Read-only: it never clicks, types or controls any window.
      """,
    parameters: [
      "type": "object",
      "properties": [
        "target": ["type": "string", "enum": ["window", "screen"],
                   "description": "What to capture: the frontmost window (default) or the whole main screen."],
        "note": ["type": "string",
                 "description": "Optional short reason shown in the execution card."]
      ],
      "required": []
    ])

  public static let all: [AgentTool] = [shell, readFile, listDir, processes, screenshot]

  /// 웹 검색 — 모델이 **모르는 세상 사실**을 직접 확인하는 손 (2026-10-27).
  /// 셸과 달리 앱이 Exa를 호출하므로 승인·샌드박스가 필요 없다(읽기 전용).
  public static let webSearch = AgentTool(
    name: "web_search",
    description: """
      Search the live web and return titles, URLs, dates and short excerpts. Use it when the \
      answer depends on facts you are not sure about, or that change over time (news, prices, \
      releases, product comparisons). Do not use it for this computer's state — that is what \
      shell and processes are for.
      """,
    parameters: [
      "type": "object",
      "properties": [
        "query": [
          "type": "string",
          "description": "A short, self-contained search query in the user's language."
        ]
      ],
      "required": ["query"]
    ])

  /// 지금 넘길 도구 목록 — 웹 검색이 준비되어 있을 때만 `web_search` 를 더한다.
  public static func available(includingWebSearch: Bool) -> [AgentTool] {
    includingWebSearch ? all + [webSearch] : all
  }

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
    너는 macOS에서 동작하는 도우미다. 사용자의 질문을 **직접 조사해서** 답한다.

    먼저 판단한다
    - 이 질문은 **이 컴퓨터의 상태**를 직접 확인해야만 답할 수 있는가?
      (디스크 용량 · 메모리(RAM) 사용량 · CPU 를 많이 쓰는 프로세스 · 네트워크 속도 · 기기 연결 상태 ·
       내 파일 목록 · 지금 설치된 앱/도구의 유무 · 네트워크 인터페이스 등)
      그렇다면 `shell` 로 명령을 실행해 **실제 값**을 확인한다. 추측으로 답하지 않는다.
    - **세상에 대한 질문은 로컬 조사 대상이 아니다.** 타 앱·제품·서비스의 장단점 비교, 일반 지식,
      최신 소식은 이 컴퓨터를 뒤져도 답이 나오지 않는다. 설치 여부를 확인해 답을 바꾸지 말고,
      `web_search` 도구가 있으면 그것으로 확인한다. 도구가 없으면 아는 범위에서 답한 뒤
      "설정 › 웹 검색을 켜면 최신 정보를 볼 수 있다"고 한 줄 안내한다.
    - 확실하지 않다고 해서 홈·/Applications·설치 목록을 넓게 훑지 않는다. 답에 필요한 범위만
      읽고, 읽은 목록을 답변에 그대로 옮기지 않는다.
    - 프로세스별 CPU·메모리는 `processes` 도구로 확인한다.
      `ps`·`top` 은 setuid 프로그램이라 샌드박스가 실행을 거부한다("Operation not permitted").
      권한을 열어도 해결되지 않으니 **다시 시도하지 말고** `processes` 를 쓴다.
    - **화면에 보이는 것**이 답에 필요하면(차트·오류 대화상자·레이아웃·영상 화면) `screenshot` 도구로
      창 또는 화면을 찍어 다음 스텝에서 본다. 글자가 많은 창은 `shell`/`read_file` 이 더 정확하다.
    - "메모리"가 나오면 보통은 **이 컴퓨터의 RAM 사용량**을 뜻한다.
      앱의 대화 기억(저장된 기록)을 물어본다고 **명확히** 말한 경우에만 그쪽을 본다.
    - 사용자가 직접 명령을 주고 싶어 하면(예: "이 명령 실행해줘") 그대로 실행한다.

    명령을 실행할 때
    - 상태를 확인하는 명령(ls, df, vm_stat, sw_vers, system_profiler, brew list, adb devices 등)은
      읽기만 하므로 그대로 실행해도 된다.
    - `ps`·`top` 은 setuid 프로그램이라 **샌드박스가 실행을 거부한다.** 권한을 열어도 안 되니
      프로세스별 CPU·메모리는 `processes` 도구로 확인한다.
    - 명령을 정확히 모르면 먼저 `--help` 또는 `man`으로 확인한다. 지식이 낡았을 수 있다.
    - 파일을 만들거나 지우거나, 설정을 바꾸거나, 뭔가를 설치하는 명령은 앱이 사용자에게 먼저 확인한다.
      확인을 받으면 **그 범위에서만** 실행된다.
    - 파괴적인 명령(rm -rf /, mkfs, dd 등)은 실행하지 않는다.
    - 한 번에 하나의 명령을 실행하고, 결과를 보고 다음을 정한다.
    - `purpose` 에 이 명령이 왜 필요한지 한 줄로 적는다(사용자에게 보이는 실행 카드에 그대로 나온다).

    답할 때
    - 실행한 결과를 그대로 옮기지 말고, **사용자에게 필요한 정보**를 중심으로 말한다.
    - 도구를 실행했다면 **그 결과의 숫자·사실로 답한다.** 결과를 쓰지 않으면 다시 확인한다.
    - 숫자는 단위와 함께 적는다(예: 521 GiB 남음, 2.25 Mbps, 32 GiB 중 11 GiB 사용).
    - 확인이 필요하면 왜 필요한지 한 줄로 밝힌다.
    """

  /// **짧은 지시문** — 온디바이스(Apple FM)용.
  /// 작은 모델은 긴 지시문을 따라가지 못한다(2026-10-22 실측: 긴 지시문에서는 도구를 안 골랐다).
  public static let compactText = """
    너는 macOS 도우미다. 질문에 답하려면 직접 확인해야 할 때가 있다.
    - 디스크·메모리(RAM)·CPU·네트워크·파일·앱·기기 같은 **이 컴퓨터의 상태**는 shell 도구로 확인한다.
    - 세상에 대한 질문(제품 비교·일반 지식·최신 소식)은 이 컴퓨터를 뒤지지 않는다. 아는 대로 답한다.
    - 프로세스별 CPU·메모리는 processes 도구를 쓴다(ps·top 은 샌드박스가 실행을 막는다).
    - "메모리"는 보통 RAM 사용량이다. 추측하지 말고 실행해서 확인한다.
    - 답에는 실행 결과의 숫자와 사실을 쓴다.
    """

  /// 앱 자신에 대한 지식 — 모델이 자기 앱과 겹치는 일을 하지 않도록 주입한다.
  /// v0.22부터는 **실제 설정값**을 넣는다(`SystemKnowledge`).
  public static func selfKnowledge(settings: QuickTalkSettings) -> String {
    SystemKnowledge.text(settings: settings)
  }
}
