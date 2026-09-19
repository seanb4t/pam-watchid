import LocalAuthentication
import SystemConfiguration

// MARK: (Re)define PAM constants here so we don't need to import .h files.

private let PAM_SUCCESS = CInt(0)
private let PAM_AUTH_ERR = CInt(9)
private let PAM_IGNORE = CInt(25)
private let PAM_SILENT = CInt(bitPattern: 0x80000000)
private let PAM_USER = CInt(2)
private let PAM_TTY = CInt(3)
private let DEFAULT_REASON = "perform an action that requires authentication"

public typealias vchar = UnsafePointer<UnsafeMutablePointer<CChar>>
public typealias pam_handle_t = UnsafeRawPointer?

// MARK: Biometric (touchID) authentication

@_cdecl("pam_sm_authenticate")
public func pam_sm_authenticate(pamh: pam_handle_t, flags: CInt, argc: CInt, argv: vchar) -> CInt {
    let sudoArguments = ProcessInfo.processInfo.arguments
    if sudoArguments.contains("-A") || sudoArguments.contains("--askpass") {
        return PAM_IGNORE
    }

    if shouldSkip(pamh: pamh) {
        return PAM_IGNORE
    }

    let arguments = parseArguments(argc: Int(argc), argv: argv)
    var reason = arguments["reason"] ?? DEFAULT_REASON
    reason = reason.isEmpty ? DEFAULT_REASON : reason

    let policy = LAPolicy.deviceOwnerAuthenticationIgnoringUserID
    
    let context = LAContext()
    if !context.canEvaluatePolicy(policy, error: nil) {
        return PAM_IGNORE
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result = PAM_AUTH_ERR
    context.evaluatePolicy(policy, localizedReason: reason) { success, error in
        defer { semaphore.signal() }

        if let error = error {
            if flags & PAM_SILENT == 0 {
                fputs("\(error.localizedDescription)\n", stderr)
            }
            result = PAM_IGNORE
            return
        }

        result = success ? PAM_SUCCESS : PAM_AUTH_ERR
    }

    semaphore.wait()
    return result
}

private func parseArguments(argc: Int, argv: vchar) -> [String: String] {
    var parsed = [String: String]()
    let arguments = UnsafeBufferPointer(start: argv, count: argc)
       .compactMap { String(cString: $0) }
       .joined(separator: " ")

    let regex = try? NSRegularExpression(pattern: "[^\\s\"']+|\"([^\"]*)\"|'([^']*)'",
                                         options: .dotMatchesLineSeparators)

    let matches = regex?.matches(in: arguments, options: .withoutAnchoringBounds,
                                 range: NSRange(location: 0, length: arguments.count))

    let nsArguments = arguments as NSString
    let groups = matches?
        .map { nsArguments.substring(with: $0.range) }
        .map { ($0 as String).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }

    for argument in groups ?? [] {
        let pieces = argument.components(separatedBy: "=")
        if pieces.count == 2, let key = pieces.first, let value = pieces.last {
            parsed[key] = value
        }
    }

    return parsed
}

// MARK: Caller context
//
// The Watch prompt appears on the console, whoever asked for it. Skipping (PAM_IGNORE) is
// always safe: the chain moves on to the password. So when the context is unclear, skip.

/// Decides, before any UI, whether this request should skip the Watch entirely.
///
/// Context available here:
///   pamItem(pamh, PAM_USER)   the user sudo is authenticating (the invoker)
///   pamItem(pamh, PAM_TTY)    the invoker's terminal; nil or "" when there is none
///   consoleUID()              uid logged in at the Mac's screen; nil at the login window
///   uid(of:)                  a user name's uid; nil when unknown
///   getenv("SSH_TTY"), getenv("SSH_CONNECTION")
private func shouldSkip(pamh: pam_handle_t) -> Bool {
    if getenv("SSH_TTY") != nil || getenv("SSH_CONNECTION") != nil {
        return true
    }
    guard let tty = pamItem(pamh, PAM_TTY), !tty.isEmpty,
          let user = pamItem(pamh, PAM_USER), let userUID = uid(of: user),
          let console = consoleUID() else {
        return true
    }
    return userUID != console
}

private typealias PamGetItem = @convention(c) (pam_handle_t, CInt, UnsafeMutablePointer<UnsafeRawPointer?>) -> CInt

/// libpam is already loaded by whichever process loaded this module, so resolve
/// pam_get_item at runtime instead of linking against it.
private let pamGetItemFunction: PamGetItem? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "pam_get_item")
    .map { unsafeBitCast($0, to: PamGetItem.self) }

/// A string-valued PAM item, or nil when it is unset or cannot be read.
private func pamItem(_ pamh: pam_handle_t, _ item: CInt) -> String? {
    guard let pamh, let pamGetItemFunction else { return nil }
    var value: UnsafeRawPointer?
    guard pamGetItemFunction(pamh, item, &value) == PAM_SUCCESS, let value else { return nil }
    return String(cString: value.assumingMemoryBound(to: CChar.self))
}

private func consoleUID() -> uid_t? {
    var uid: uid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?, name != "loginwindow" else {
        return nil
    }
    return uid
}

private func uid(of user: String) -> uid_t? {
    getpwnam(user).map { $0.pointee.pw_uid }
}

private extension LAPolicy {
    static var deviceOwnerAuthenticationIgnoringUserID: LAPolicy {
#if canImport(CoreHID) // Check for the 15.0 SDK
        if #available(macOS 15, *) {
            return .deviceOwnerAuthenticationWithBiometricsOrCompanion
        } else {
            return .deviceOwnerAuthenticationWithBiometricsOrWatch
        }
#else
        return .deviceOwnerAuthenticationWithBiometricsOrWatch
#endif
    }
}

// MARK: - Ignored (unhandled) PAM events

@_cdecl("pam_sm_chauthtok")
public func pam_sm_chauthtok(pamh: pam_handle_t, flags: CInt, argc: CInt, argv: vchar) -> CInt {
    return PAM_IGNORE
}

@_cdecl("pam_sm_setcred")
public func pam_sm_setcred(pamh: pam_handle_t, flags: CInt, argc: CInt, argv: vchar) -> CInt {
    return PAM_IGNORE
}

@_cdecl("pam_sm_acct_mgmt")
public func pam_sm_acct_mgmt(pamh: pam_handle_t, flags: CInt, argc: CInt, argv: vchar) -> CInt {
    return PAM_IGNORE
}
