import AppKit
import Security
import TiroirCore

/// What Tiroir knows about an app that owns icons: its name and icon for the drawers, its declared App Store category
/// and its developer for Smart Sort.
public struct AppInfo {
    public var bundleID: String
    public var name: String
    public var icon: NSImage
    public var bundleURL: URL?
    public var appStoreCategory: String?
    public var developer: String
}

/// Looks apps up once and remembers them. Reading a code signature takes a few milliseconds, so it happens once per
/// app and per launch of Tiroir.
@MainActor
public final class AppDirectory {
    private var cache: [String: AppInfo] = [:]
    /// Demo mode replaces real apps with generic ones, so captures never show someone's own apps.
    public var overrides: [String: AppInfo] = [:]

    public init() {}

    public func info(bundleID: String, url: URL?, fallbackName: String) -> AppInfo {
        if let override = overrides[bundleID] { return override }
        if let cached = cache[bundleID] { return cached }
        let location = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let bundle = location.flatMap(Bundle.init(url:))
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackName
        let icon = location.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        let category = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        let summary = location.flatMap(Self.signingSummary(of:))
        let info = AppInfo(
            bundleID: bundleID, name: name.isEmpty ? fallbackName : name, icon: icon, bundleURL: location,
            appStoreCategory: category,
            developer: DeveloperName.from(certificateSummary: summary, bundleID: bundleID, appName: name))
        cache[bundleID] = info
        return info
    }

    public func forget(_ bundleID: String) {
        cache[bundleID] = nil
    }

    /// The subject of the app's leaf signing certificate: "Developer ID Application: Proton AG (2SB5Z68H26)".
    nonisolated static func signingSummary(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }
}
