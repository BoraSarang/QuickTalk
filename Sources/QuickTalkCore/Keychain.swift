import Foundation
import Security

/// [DEPRECATED] 키체인 저장소 — 현재 사용하지 않는다.
/// 앱 실행 때마다 접근 허용 프롬프트가 떠 사용자 요청으로 `SecretStore`(로컬 파일)로 대체했다.
/// 과거 저장 키를 되살릴 때만 참고용으로 남겨 둔다.
@available(*, deprecated, message: "SecretStore를 사용하세요")
public enum KeychainHelper {
  public static func save(account: String, service: String = "com.borasarang.QuickTalk.llm", secret: String) -> Bool {
    guard let data = secret.data(using: .utf8) else { return false }
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: service,
                             kSecAttrAccount as String: account]
    SecItemDelete(q as CFDictionary)
    let add = q.merging([kSecValueData as String: data]) { $1 }
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }
  public static func load(account: String, service: String = "com.borasarang.QuickTalk.llm") -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: service,
                             kSecAttrAccount as String: account,
                             kSecReturnData as String: true,
                             kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  public static func delete(account: String, service: String = "com.borasarang.QuickTalk.llm") -> Bool {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: service,
                             kSecAttrAccount as String: account]
    let status = SecItemDelete(q as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
