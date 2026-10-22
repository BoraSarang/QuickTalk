import Foundation
#if canImport(Darwin)
import Darwin
#endif

// [FEATURE] 단일 실행 잠금 — flock(2) 기반 (2026-10-22)
//
// 앱이 두 번 실행되면 메뉴바 아이콘·대화 창·포인터 pill 이 각각 생긴다.
// 설치본과 디버그 빌드처럼 실행 파일 경로가 달라도 하나로 보려면 **공용 잠금 파일**이 필요하다.
//
// PID 파일만 쓰면 비정상 종료 뒤 찌꺼기가 남아 앱이 영영 안 뜰 수 있다.
// flock 은 열린 파일 기술자에 묶이므로 **프로세스가 끝나면 OS 가 자동으로 푼다.**

public final class InstanceLock {
  public let path: String
  private var descriptor: Int32 = -1

  public init(path: String) {
    self.path = path
  }

  /// 잠금을 잡고 있으면 true.
  public var isHeld: Bool { descriptor >= 0 }

  /// 잠금을 시도한다 — 이미 다른 프로세스(또는 다른 기술자)가 잡고 있으면 false.
  @discardableResult
  public func acquire() -> Bool {
    guard descriptor < 0 else { return true }
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return false }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      close(fd)
      return false
    }
    // 진단용 PID — 판정 자체는 flock 이 한다.
    ftruncate(fd, 0)
    let line = "\(getpid())\n"
    _ = line.withCString { write(fd, $0, strlen($0)) }
    descriptor = fd
    return true
  }

  public func release() {
    guard descriptor >= 0 else { return }
    flock(descriptor, LOCK_UN)
    close(descriptor)
    descriptor = -1
  }

  deinit { release() }
}
