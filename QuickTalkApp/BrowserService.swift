import Foundation
import WebKit

// [FEATURE] 격리 브라우저 (v0.38.1, PLAN_v0.38.1 §5·§6)
//
// Safari 와 **쿠키·캐시를 공유하지 않는** 전용 프로필로 웹 페이지를 연다.
// 창은 화면 밖(-12000, -12000)에 두고 키·메인이 될 수 없게 해서 **포커스 스틸이 없다**.
//
// 이 클래스는 "페이지를 어떻게 열고 읽고 누르는가"만 안다. 승인·감사·출처·게이트는
// `AgentExecutor+Browser.swift` 가 맡는다 — 그래야 브라우저도 기존 신뢰 모델을 그대로 탄다.
//
// 차단(PLAN §5.4): 다운로드 · 새 창/팝업 · JS 다이얼로그 · 파일 선택 · 미디어 권한 ·
// HTTP 인증 · TLS 우회. 모두 열지 않는다.

@MainActor
final class BrowserService: NSObject {
  enum ServiceError: Error, Equatable {
    case notLoaded
    case elementNotFound
    case unsupportedElement(String)
    case sensitiveField
    case noForm
    case formInvalid
    case blocked(String)
    case loadFailed(String)
    case invalidReference

    var userText: String {
      switch self {
      case .notLoaded:
        return L("아직 열린 페이지가 없습니다. browser_open 으로 먼저 페이지를 여세요.")
      case .elementNotFound:
        return L("그 참조를 찾지 못했습니다. 페이지가 바뀌었을 수 있으니 browser_read 로 다시 읽으세요.")
      case .unsupportedElement(let kind):
        return Lf("이 요소(%@)는 그 도구로 조작할 수 없습니다.", kind)
      case .sensitiveField:
        return L("비밀번호·파일·숨김·결제·인증번호 필드는 읽지도 입력하지도 않습니다.")
      case .noForm:
        return L("그 요소가 속한 양식을 찾지 못했습니다.")
      case .formInvalid:
        return L("필수 항목이 비어 있어 브라우저가 제출을 막았습니다. browser_read 로 양식을 확인하세요.")
      case .blocked(let reason):
        return reason
      case .loadFailed(let detail):
        return Lf("페이지를 열지 못했습니다: %@", detail)
      case .invalidReference:
        return L("참조 형식이 올바르지 않습니다(e1, e2, …).")
      }
    }
  }

  /// 승인 카드에 보여 줄 클릭 설명.
  struct ClickPlan {
    let element: BrowserElement
    /// 링크 이동이면 목적지. 그 밖에는 nil.
    let destination: URL?
    /// 링크이고 위험 신호가 없으면 읽기 — 그 외는 **항상 승인**.
    let isReadOnlyLink: Bool
  }

  /// 승인 카드에 보여 줄 양식 설명.
  struct FormPlan {
    let form: BrowserForm
    let actionURL: URL?
    let isCrossSite: Bool
    let method: String
    let fieldNames: [String]
  }

  let profileID: UUID
  private let webView: WKWebView
  private let window: OffscreenWindow
  private var lastSnapshot: BrowserPageSnapshot?
  private var lastURL: URL?
  /// 다운로드·새 창처럼 **앱이 막은 동작** — 다음 스냅샷에 한 줄로 붙인다.
  private var notice: String?
  /// 마지막 내비게이션 실패 — 다음 스냅샷에서 오류로 올린다.
  private var lastNavigationError: String?

  init(profileID: UUID) {
    self.profileID = profileID
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.preferences.isFraudulentWebsiteWarningEnabled = true

    let frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
    webView = WKWebView(frame: frame, configuration: configuration)
    window = OffscreenWindow(contentRect: frame,
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
    super.init()

    window.contentView = webView
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.hasShadow = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.collectionBehavior = [.transient, .ignoresCycle]
    window.setFrameOrigin(NSPoint(x: -12_000, y: -12_000))
    // 보이지 않는 위치에 두되 **창은 살아 있게** 한다 — WKWebView 가 화면 밖에서도
    // 레이아웃·자바스크립트를 정상적으로 돌리기 위해서다. orderFrontRegardless 는
    // 앱을 활성화하지 않고 포커스도 가져오지 않는다.
    window.orderFrontRegardless()

    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = false
    if #available(macOS 13.3, *) {
      webView.isInspectable = false
    }
  }

  /// 페이지를 열고 스냅샷을 돌려준다.
  func open(_ url: URL, maxCharacters: Int) async throws -> BrowserPageSnapshot {
    guard BrowserURLPolicy.navigationBlockReason(url) == nil else {
      throw ServiceError.blocked(BrowserURLPolicy.navigationBlockReason(url) ?? "")
    }
    lastNavigationError = nil
    notice = nil
    webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    await waitUntilSettled(timeout: 25)
    try throwNavigationErrorIfNeeded()
    return try await snapshot(maxCharacters: maxCharacters)
  }

  /// 현재 페이지를 다시 읽는다.
  func current(maxCharacters: Int) async throws -> BrowserPageSnapshot {
    guard let url = webView.url, url.absoluteString != "about:blank" else {
      throw ServiceError.notLoaded
    }
    return try await snapshot(maxCharacters: maxCharacters)
  }

  /// 뒤로 한 페이지.
  func back(maxCharacters: Int) async throws -> BrowserPageSnapshot {
    guard webView.canGoBack else {
      throw ServiceError.unsupportedElement(L("뒤로 갈 기록"))
    }
    lastNavigationError = nil
    webView.goBack()
    await waitUntilSettled(timeout: 20)
    try throwNavigationErrorIfNeeded()
    return try await snapshot(maxCharacters: maxCharacters)
  }

  /// 참조의 클릭 계획 — 승인 필요 여부와 목적지를 정한다. 실행은 하지 않는다.
  func clickPlan(ref: String) throws -> ClickPlan {
    let element = try element(ref: ref)
    guard !element.disabled else {
      throw ServiceError.unsupportedElement(L("비활성 요소"))
    }
    guard !element.download else {
      throw ServiceError.unsupportedElement(L("다운로드 링크"))
    }
    guard element.isLink else {
      return ClickPlan(element: element, destination: nil, isReadOnlyLink: false)
    }
    guard !element.href.isEmpty, let url = URL(string: element.href) else {
      return ClickPlan(element: element, destination: nil, isReadOnlyLink: false)
    }
    if let reason = BrowserURLPolicy.navigationBlockReason(url) {
      throw ServiceError.blocked(reason)
    }
    let safe = !BrowserURLPolicy.linkNeedsApproval(url)
    return ClickPlan(element: element, destination: url, isReadOnlyLink: safe)
  }

  /// 클릭 실행 — 링크는 같은 창에서 직접 이동한다(새 창·팝업을 만들지 않는다).
  func performClick(ref: String, maxCharacters: Int) async throws -> BrowserPageSnapshot {
    let plan = try clickPlan(ref: ref)
    notice = nil
    lastNavigationError = nil
    if let destination = plan.destination {
      // 같은 문서 안의 앵커(#section)는 스크롤만 한다 — JS 클릭이 맞다.
      if let current = webView.url, Self.sameDocument(current, destination),
         current.absoluteString != destination.absoluteString {
        _ = try await evaluate(Self.clickJS(ref: ref))
        await waitUntilSettled(timeout: 4)
      } else {
        webView.load(URLRequest(url: destination, cachePolicy: .useProtocolCachePolicy,
                                timeoutInterval: 30))
        await waitUntilSettled(timeout: 25)
      }
    } else {
      let result = try await evaluate(Self.clickJS(ref: ref))
      if let message = result as? String, !message.isEmpty {
        throw ServiceError.unsupportedElement(message)
      }
      await waitUntilSettled(timeout: 8)
    }
    try throwNavigationErrorIfNeeded()
    return try await snapshot(maxCharacters: maxCharacters)
  }

  /// 텍스트 입력·선택 — 페이지를 이동시키지 않는다.
  func type(ref: String, text: String) async throws -> BrowserElement {
    let element = try element(ref: ref)
    guard !element.disabled else {
      throw ServiceError.unsupportedElement(L("비활성 요소"))
    }
    guard !Self.isSensitiveElement(element) else { throw ServiceError.sensitiveField }
    switch element.kind {
    case "input", "textarea", "select":
      break
    default:
      throw ServiceError.unsupportedElement(element.kind)
    }
    let payload = Self.jsString(text)
    let refLiteral = Self.jsString(ref)
    let script = """
      (() => {
        const el = document.querySelector('[data-qt-ref="' + \(refLiteral) + '"]');
        if (!el) return 'missing';
        const text = \(payload);
        if (el.tagName === 'SELECT') {
          const want = text.toLowerCase();
          let hit = null;
          for (const option of el.options) {
            if ((option.value || '').toLowerCase() === want
                || (option.textContent || '').trim().toLowerCase() === want) { hit = option; break; }
          }
          if (!hit) return 'option';
          el.value = hit.value;
        } else {
          const proto = el.tagName === 'TEXTAREA'
            ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
          setter.call(el, text);
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return '';
      })()
      """
    let result = try await evaluate(script)
    if let message = result as? String, !message.isEmpty {
      if message == "option" {
        throw ServiceError.unsupportedElement(L("그 선택지"))
      }
      throw ServiceError.elementNotFound
    }
    return element
  }

  /// 제출 계획 — 승인 카드에 쓸 메서드·목적지·필드 이름.
  func formPlan(ref: String) throws -> FormPlan {
    let element = try element(ref: ref)
    guard element.formIndex >= 0, let snapshot = lastSnapshot,
          let form = snapshot.forms.first(where: { $0.index == element.formIndex }) else {
      throw ServiceError.noForm
    }
    let actionURL = URL(string: form.action)
    let crossSite: Bool
    if let actionURL, let currentHost = webView.url?.host?.lowercased(),
       let actionHost = actionURL.host?.lowercased() {
      crossSite = currentHost != actionHost
    } else {
      crossSite = false
    }
    let method = form.method.isEmpty ? "GET" : form.method.uppercased()
    let names = form.fields.map { $0.name.isEmpty ? $0.label : $0.name }
      .filter { !$0.isEmpty }
    return FormPlan(form: form, actionURL: actionURL, isCrossSite: crossSite,
                    method: method, fieldNames: Array(names.prefix(20)))
  }

  /// 양식 제출 — 브라우저 검증을 통과한 뒤에만 실제로 보낸다.
  func performSubmit(ref: String, maxCharacters: Int) async throws -> BrowserPageSnapshot {
    _ = try formPlan(ref: ref)
    notice = nil
    lastNavigationError = nil
    let script = """
      (() => {
        const el = document.querySelector('[data-qt-ref="' + \(Self.jsString(ref)) + '"]');
        if (!el) return 'missing';
        const form = el.closest('form');
        if (!form) return 'no-form';
        if (!form.checkValidity()) return 'invalid';
        if (typeof form.requestSubmit === 'function') { form.requestSubmit(); }
        else { form.submit(); }
        return '';
      })()
      """
    let result = try await evaluate(script)
    if let message = result as? String, !message.isEmpty {
      switch message {
      case "missing": throw ServiceError.elementNotFound
      case "no-form": throw ServiceError.noForm
      default: throw ServiceError.formInvalid
      }
    }
    await waitUntilSettled(timeout: 25)
    try throwNavigationErrorIfNeeded()
    return try await snapshot(maxCharacters: maxCharacters)
  }

  /// 마지막 스냅샷의 참조를 요소로 되돌린다.
  func element(ref: String) throws -> BrowserElement {
    guard Self.isValidReference(ref) else { throw ServiceError.invalidReference }
    guard let snapshot = lastSnapshot else { throw ServiceError.notLoaded }
    if let element = snapshot.elements.first(where: { $0.ref == ref }) {
      return element
    }
    for form in snapshot.forms {
      if let field = form.fields.first(where: { $0.ref == ref }) {
        return BrowserElement(ref: field.ref, kind: field.type, tag: "input",
                              type: field.type, name: field.name, label: field.label,
                              formIndex: form.index, required: field.required,
                              valueLength: field.valueLength)
      }
    }
    throw ServiceError.elementNotFound
  }

  /// 현재 주소 — 감사·출처에 쓴다.
  var currentURL: URL? { webView.url }
  var currentTitle: String { lastSnapshot?.title ?? webView.title ?? "" }

  /// QA 전용 — 네트워크 없이 로컬 HTML을 넣고 스냅샷을 돌려준다.
  /// `--qa-browser-live` 가 제목·본문·링크·양식·민감 필드 제외를 실제 WebKit으로 확인한다.
  func loadHTMLForQA(_ html: String,
                     baseURL: URL? = URL(string: "https://example.com/qa")) async throws -> BrowserPageSnapshot {
    lastNavigationError = nil
    notice = nil
    webView.loadHTMLString(html, baseURL: baseURL)
    await waitUntilSettled(timeout: 10)
    try throwNavigationErrorIfNeeded()
    return try await snapshot(maxCharacters: 20_000)
  }

  /// 창·웹뷰를 정리한다. 15분 유휴 정리에서 부른다.
  func teardown() {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    window.contentView = nil
    window.orderOut(nil)
    window.close()
  }

  /// 프로필의 쿠키·캐시·로컬 저장소를 모두 지운다.
  static func clearData(profileID: UUID) async {
    let store = WKWebsiteDataStore(forIdentifier: profileID)
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      store.removeData(ofTypes: types, modifiedSince: .distantPast) {
        cont.resume()
      }
    }
  }

  // MARK: - 내부

  /// 로딩이 끝날 때까지 기다린다. `didFinish` 만 믿지 않고 `isLoading` 을 폴링한다 —
  /// 같은 문서 안 이동·자바스크립트 렌더링은 델리게이트가 오지 않을 수 있다.
  private func waitUntilSettled(timeout: TimeInterval) async {
    let deadline = Date().addingTimeInterval(timeout)
    try? await Task.sleep(nanoseconds: 250_000_000)
    while webView.isLoading && Date() < deadline && !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 120_000_000)
    }
    // 늦게 그려지는 페이지(SPA)를 위해 한 번 더 숨을 고른다.
    try? await Task.sleep(nanoseconds: 350_000_000)
  }

  private func throwNavigationErrorIfNeeded() throws {
    if let error = lastNavigationError {
      lastNavigationError = nil
      throw ServiceError.loadFailed(error)
    }
  }

  private func snapshot(maxCharacters: Int) async throws -> BrowserPageSnapshot {
    let raw = try await evaluate(Self.snapshotJS)
    guard let json = raw as? String, let data = json.data(using: .utf8) else {
      throw ServiceError.loadFailed(L("페이지 내용을 읽지 못했습니다."))
    }
    var page: BrowserPageSnapshot
    do {
      page = try JSONDecoder().decode(BrowserPageSnapshot.self, from: data)
    } catch {
      throw ServiceError.loadFailed(L("페이지 내용을 해석하지 못했습니다."))
    }
    if let notice, !notice.isEmpty {
      page.notice = notice
      self.notice = nil
    }
    lastSnapshot = page
    lastURL = webView.url
    return page
  }

  @discardableResult
  private func evaluate(_ script: String) async throws -> Any? {
    do {
      return try await webView.evaluateJavaScript(script)
    } catch {
      throw ServiceError.loadFailed(error.localizedDescription)
    }
  }

  private static func isValidReference(_ ref: String) -> Bool {
    ref.range(of: #"^e[0-9]{1,4}$"#, options: .regularExpression) != nil
  }

  /// 두 URL 이 같은 문서인가 — 프래그먼트만 다른 경우.
  private static func sameDocument(_ lhs: URL, _ rhs: URL) -> Bool {
    guard var a = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
          var b = URLComponents(url: rhs, resolvingAgainstBaseURL: false) else { return false }
    a.fragment = nil
    b.fragment = nil
    return a.url == b.url
  }

  /// 비밀번호·파일·숨김·결제·인증번호로 보이는 요소인가 — 이중 확인용.
  static func isSensitiveElement(_ element: BrowserElement) -> Bool {
    let type = element.type.lowercased()
    if ["password", "file", "hidden"].contains(type) { return true }
    let hint = (element.name + " " + element.label).lowercased()
    let risky = ["password", "passwd", "pwd", "card", "cvc", "cvv", "credit",
                 "security code", "otp", "one-time", "ssn", "social security",
                 "routing", "iban", "비밀번호", "카드", "인증번호", "주민"]
    return risky.contains { hint.contains($0) }
  }

  /// JS 문자열 리터럴로 안전하게 감싼다.
  static func jsString(_ value: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [value])
    guard let data, let array = String(data: data, encoding: .utf8),
          array.count >= 2 else { return "\"\"" }
    return String(array.dropFirst().dropLast())
  }

  private static func clickJS(ref: String) -> String {
    """
    (() => {
      const el = document.querySelector('[data-qt-ref="' + \(jsString(ref)) + '"]');
      if (!el) return 'missing';
      if (el.disabled) return 'disabled';
      el.click();
      return '';
    })()
    """
  }

  // MARK: - 페이지 스냅샷 JS
  //
  // ① 비밀번호·파일·숨김·결제·인증번호 필드는 **아예 ref 를 주지 않는다**(값도 보내지 않는다).
  // ② 링크·버튼·입력·선택·체크박스에 e1, e2, … 참조를 붙인다(최대 80개).
  // ③ 양식은 action·method·필드 이름·필수 여부·입력된 글자 수만 보낸다.
  private static let snapshotJS = #"""
    (() => {
      const MAX_ELEMENTS = 80;
      const MAX_TEXT = 60000;
      const MAX_LABEL = 90;
      const elements = [];
      const forms = [];
      let counter = 0;
      let truncated = false;

      document.querySelectorAll('[data-qt-ref]').forEach((el) => el.removeAttribute('data-qt-ref'));

      const clean = (s) => (s || '').replace(/\s+/g, ' ').trim().slice(0, MAX_LABEL);

      const sensitiveAutocomplete = /(current-password|new-password|one-time-code|cc-number|cc-csc|cc-exp|cc-name)/i;
      const sensitiveName = /(pass(word)?|pwd|card|cvc|cvv|ccnum|credite?card|security.?code|otp|one.?time|ssn|social.?security|routing|iban|account.?number|비밀번호|카드|인증번호)/i;

      const isSensitive = (el) => {
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (type === 'password' || type === 'file' || type === 'hidden') return true;
        const ac = el.getAttribute('autocomplete') || '';
        if (sensitiveAutocomplete.test(ac)) return true;
        const hint = (el.getAttribute('name') || '') + ' ' + (el.getAttribute('id') || '')
          + ' ' + (el.getAttribute('placeholder') || '') + ' ' + (el.getAttribute('aria-label') || '');
        return sensitiveName.test(hint);
      };

      const labelOf = (el) => {
        const aria = el.getAttribute('aria-label');
        if (aria) return clean(aria);
        const labelledby = el.getAttribute('aria-labelledby');
        if (labelledby) {
          const node = document.getElementById(labelledby);
          if (node) return clean(node.innerText || node.textContent || '');
        }
        if (el.id) {
          const label = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
          if (label) return clean(label.innerText || label.textContent || '');
        }
        const wrapping = el.closest('label');
        if (wrapping) return clean(wrapping.innerText || wrapping.textContent || '');
        const placeholder = el.getAttribute('placeholder');
        if (placeholder) return clean(placeholder);
        const title = el.getAttribute('title');
        if (title) return clean(title);
        const tag = el.tagName.toLowerCase();
        if (tag === 'button' || tag === 'a' || tag === 'summary') {
          return clean(el.innerText || el.textContent || '');
        }
        const value = el.getAttribute('value');
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (value && (type === 'submit' || type === 'button' || type === 'reset')) return clean(value);
        return clean(el.getAttribute('name') || '');
      };

      const kindOf = (el) => {
        const tag = el.tagName.toLowerCase();
        if (tag === 'a') {
          const href = (el.getAttribute('href') || '').trim();
          if (/^https?:/i.test(href) || href.startsWith('#')) return 'link';
          return 'button';
        }
        if (tag === 'button' || tag === 'summary') return 'button';
        if (tag === 'textarea') return 'textarea';
        if (tag === 'select') return 'select';
        if (tag === 'input') {
          const type = (el.getAttribute('type') || 'text').toLowerCase();
          if (type === 'submit' || type === 'image') return 'submit';
          if (type === 'button' || type === 'reset') return 'button';
          if (type === 'checkbox') return 'checkbox';
          if (type === 'radio') return 'radio';
          return 'input';
        }
        return 'button';
      };

      const refFor = (el) => {
        const existing = el.getAttribute('data-qt-ref');
        if (existing) return existing;
        if (counter >= MAX_ELEMENTS) { truncated = true; return null; }
        counter += 1;
        const ref = 'e' + counter;
        el.setAttribute('data-qt-ref', ref);
        return ref;
      };

      const formNodes = Array.from(document.querySelectorAll('form'));
      const formIndexOf = (el) => {
        const form = el.closest ? el.closest('form') : null;
        if (!form) return -1;
        const idx = formNodes.indexOf(form);
        return idx >= 0 && idx < 10 ? idx : -1;
      };

      const makeElement = (el, kind, href) => {
        const ref = refFor(el);
        if (!ref) return null;
        const tag = el.tagName.toLowerCase();
        const type = (el.getAttribute('type') || '').toLowerCase();
        const valueLength = (typeof el.value === 'string') ? el.value.length : 0;
        const options = tag === 'select'
          ? Array.from(el.options).slice(0, 40).map((o) => clean(o.textContent || o.value))
          : [];
        const object = {
          ref: ref,
          kind: kind,
          tag: tag,
          type: type,
          name: (el.getAttribute('name') || '').slice(0, 80),
          label: labelOf(el),
          href: href || '',
          formIndex: formIndexOf(el),
          required: !!el.required,
          download: el.hasAttribute('download'),
          disabled: !!el.disabled,
          valueLength: valueLength,
          options: options
        };
        elements.push(object);
        return object;
      };

      for (const form of formNodes.slice(0, 10)) {
        const fields = [];
        let sensitive = 0;
        const nodes = Array.from(form.querySelectorAll('input, textarea, select'));
        for (const node of nodes) {
          if (isSensitive(node)) { sensitive += 1; continue; }
          const object = makeElement(node, kindOf(node), '');
          if (!object) continue;
          fields.push({
            ref: object.ref,
            name: object.name,
            type: object.type || node.tagName.toLowerCase(),
            label: object.label,
            required: object.required,
            valueLength: object.valueLength,
            options: object.options
          });
        }
        forms.push({
          index: forms.length,
          action: (form.action || form.getAttribute('action') || location.href).slice(0, 500),
          method: (form.method || form.getAttribute('method') || 'get').toLowerCase(),
          fields: fields,
          sensitiveCount: sensitive
        });
      }

      const candidates = Array.from(document.querySelectorAll(
        'a[href], button, input, textarea, select, [role="button"], [role="tab"], summary'
      ));
      for (const el of candidates) {
        if (el.hasAttribute('data-qt-ref')) continue;
        if (isSensitive(el)) continue;
        const style = window.getComputedStyle(el);
        if (style.visibility === 'hidden' || style.display === 'none' || style.opacity === '0') continue;
        if (el.getClientRects().length === 0) continue;
        const kind = kindOf(el);
        let href = '';
        if (kind === 'link') {
          try { href = new URL(el.getAttribute('href'), location.href).href.slice(0, 500); } catch (_) {}
        }
        makeElement(el, kind, href);
      }

      const body = document.body;
      const text = body ? (body.innerText || body.textContent || '') : '';
      return JSON.stringify({
        url: location.href,
        title: document.title || '',
        text: text.slice(0, MAX_TEXT),
        elements: elements,
        forms: forms,
        truncated: truncated
      });
    })()
    """#
}

/// 화면 밖으로만 존재하는 창 — 키·메인이 될 수 없어 포커스를 빼앗지 않는다.
private final class OffscreenWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// MARK: - 내비게이션 정책

extension BrowserService: WKNavigationDelegate {
  func webView(_ webView: WKWebView,
               decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if navigationAction.shouldPerformDownload {
      notice = L("다운로드는 지원하지 않습니다. 필요하면 사용자에게 주소를 알려 주세요.")
      decisionHandler(.cancel)
      return
    }
    guard let url = navigationAction.request.url else {
      decisionHandler(.allow)
      return
    }
    // about:blank 는 초기 상태 — 그 밖의 비-http(s)는 모두 막는다.
    if url.absoluteString == "about:blank" {
      decisionHandler(.allow)
      return
    }
    if let reason = BrowserURLPolicy.navigationBlockReason(url) {
      if navigationAction.targetFrame?.isMainFrame == true {
        notice = reason
        lastNavigationError = reason
      }
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView,
               decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if let http = navigationResponse.response as? HTTPURLResponse,
       let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
       disposition.contains("attachment") {
      notice = L("다운로드는 지원하지 않습니다.")
      decisionHandler(.cancel)
      return
    }
    guard navigationResponse.canShowMIMEType else {
      notice = L("이 형식은 브라우저에서 열 수 없습니다(다운로드 차단).")
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    lastNavigationError = nil
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    lastNavigationError = (error as NSError).localizedDescription
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    let nsError = error as NSError
    // 취소는 우리가 정책으로 막은 경우에도 온다 — 사용자에게는 정책 안내를 그대로 보여 준다.
    if nsError.code == NSURLErrorCancelled { return }
    lastNavigationError = nsError.localizedDescription
  }

  func webView(_ webView: WKWebView,
               didReceive challenge: URLAuthenticationChallenge,
               completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // 서버 인증서는 시스템 기본 검증에 맡긴다(우회하지 않는다). HTTP 인증·클라이언트
    // 인증서는 비밀번호 창을 띄우지 않도록 취소한다.
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      notice = L("이 페이지는 로그인(HTTP 인증)이 필요해 열 수 없습니다.")
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    lastNavigationError = L("페이지 프로세스가 예기치 않게 종료되었습니다. browser_open 으로 다시 여세요.")
  }
}

// MARK: - UI 정책 (새 창·다이얼로그·파일·미디어 차단)

extension BrowserService: WKUIDelegate {
  func webView(_ webView: WKWebView,
               createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction,
               windowFeatures: WKWindowFeatures) -> WKWebView? {
    notice = L("새 창·팝업은 열지 않습니다. 같은 창에서 열 수 있는 링크를 사용하세요.")
    return nil
  }

  func webView(_ webView: WKWebView,
               runJavaScriptAlertPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping () -> Void) {
    notice = Lf("페이지 알림: %@", String(message.prefix(120)))
    completionHandler()
  }

  func webView(_ webView: WKWebView,
               runJavaScriptConfirmPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping (Bool) -> Void) {
    notice = L("페이지가 확인 창을 띄웠지만 앱은 자동으로 취소합니다.")
    completionHandler(false)
  }

  func webView(_ webView: WKWebView,
               runJavaScriptTextInputPanelWithPrompt prompt: String,
               defaultText: String?,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping (String?) -> Void) {
    notice = L("페이지가 입력 창을 띄웠지만 앱은 자동으로 취소합니다.")
    completionHandler(nil)
  }

  func webView(_ webView: WKWebView,
               runOpenPanelWith parameters: WKOpenPanelParameters,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping ([URL]?) -> Void) {
    notice = L("파일 선택은 지원하지 않습니다.")
    completionHandler(nil)
  }

  @available(macOS 12.0, *)
  func webView(_ webView: WKWebView,
               requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo,
               type: WKMediaCaptureType,
               decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    notice = L("카메라·마이크·화면 접근은 허용하지 않습니다.")
    decisionHandler(.deny)
  }
}
