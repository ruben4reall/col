import Foundation
@testable import ColShell
import Testing

struct AppLocationTests {
    @Test func buildFoldersAreDevelopment() {
        #expect(AppLocation.isDevelopmentPath("/Users/me/col/.build/xcode/Build/Products/Debug/Col.app"))
        #expect(AppLocation.isDevelopmentPath("/Users/me/Library/Developer/Xcode/DerivedData/Col-abc/Build/Products/Debug/Col.app"))
        // scripts/build.sh with COL_BUILD_DIR, outside the clone.
        #expect(AppLocation.isDevelopmentPath("/Users/me/Library/Caches/Col/Xcode/Build/Products/Release/Col.app"))
        #expect(AppLocation.isDevelopmentPath("/tmp/release/Col.xcarchive/Products/Applications/Col.app"))
        #expect(!AppLocation.isDevelopmentPath("/Applications/Col.app"))
        #expect(!AppLocation.isDevelopmentPath("/Users/me/Downloads/Col.app"))
    }

    @Test func applicationsFoldersAreTheMacsAndTheUsers() {
        #expect(AppLocation.isInApplications(URL(fileURLWithPath: "/Applications/Col.app"), home: "/Users/me"))
        #expect(AppLocation.isInApplications(URL(fileURLWithPath: "/Applications/Utilities/Col.app"), home: "/Users/me"))
        #expect(AppLocation.isInApplications(URL(fileURLWithPath: "/Users/me/Applications/Col.app"), home: "/Users/me"))
        #expect(!AppLocation.isInApplications(URL(fileURLWithPath: "/Volumes/Col/Col.app"), home: "/Users/me"))
        #expect(!AppLocation.isInApplications(URL(fileURLWithPath: "/Users/me/Downloads/Col.app"), home: "/Users/me"))
        #expect(!AppLocation.isInApplications(URL(fileURLWithPath: "/Users/other/Applications/Col.app"), home: "/Users/me"))
    }

    @Test func aWritableFolderIsNotPassingThrough() {
        // A mounted disk image reads as read-only; a folder of the user's, or nothing at all, does not.
        #expect(!AppLocation.isReadOnly(FileManager.default.temporaryDirectory))
        #expect(!AppLocation.isReadOnly(URL(fileURLWithPath: "/nowhere/Col.app")))
    }

    @Test func quarantineIsTakenOffTheWholeApp() throws {
        let files = FileManager.default
        let app = files.temporaryDirectory.appendingPathComponent("col-qtn-\(UUID().uuidString)/Col.app")
        defer { try? files.removeItem(at: app.deletingLastPathComponent()) }
        let executable = app.appendingPathComponent("Contents/MacOS/Col")
        try files.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.createFile(atPath: executable.path, contents: Data("x".utf8))
        let value = Array("0281;00000000;;".utf8)
        for path in [app.path, executable.path] {
            #expect(setxattr(path, "com.apple.quarantine", value, value.count, 0, XATTR_NOFOLLOW) == 0)
        }
        #expect(AppLocation.isQuarantined(app))

        #expect(AppLocation.removeQuarantine(from: app))

        #expect(!AppLocation.isQuarantined(app))
        #expect(getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) < 0)
    }
}
