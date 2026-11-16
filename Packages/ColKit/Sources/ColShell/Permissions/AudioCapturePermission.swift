import Foundation

/// The permission to record system audio, which the bars that follow the sound need. macOS offers no public way to
/// read whether it was given, nor to ask for it before recording: TCC's own two functions are looked up at run time.
/// Without them the state reads unknown, and macOS asks by itself the first time Col listens.
enum AudioCapturePermission {
    enum Status: Equatable {
        case granted, denied
        /// Not asked yet, or not readable on this macOS.
        case unknown
    }

    private static let service = "kTCCServiceAudioCapture"
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }

    static var status: Status {
        guard let preflight = symbol("TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(preflight, to: Preflight.self)(service as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Shows macOS's question. False when it cannot be asked from here: then it is asked when Col first listens.
    @discardableResult
    static func request(_ answered: @escaping @Sendable (Bool) -> Void) -> Bool {
        guard let request = symbol("TCCAccessRequest") else { return false }
        unsafeBitCast(request, to: Request.self)(service as CFString, nil) { granted in answered(granted) }
        return true
    }
}
