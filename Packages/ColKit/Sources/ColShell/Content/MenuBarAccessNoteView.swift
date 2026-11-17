import ApplicationServices
import SwiftUI

/// What the island says once when it cannot see the menu bar: without Accessibility (Device Control and Data Access on
/// macOS 27), its wings keep to a narrow width rather than guess where the menus and icons are.
struct MenuBarAccessNoteView: View {
    @State private var granted = AXIsProcessTrusted()

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Let Col see the menu bar", bundle: .module)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(granted ? "Thank you: the wings now keep clear of every menu and icon." : detail, bundle: .module)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !granted {
                Button {
                    PermissionCenter.shared.request(.accessibility)
                } label: {
                    Text("Allow…", bundle: .module)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = AXIsProcessTrusted()
        }
    }

    private var detail: LocalizedStringKey {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
            ? "With Device Control and Data Access, its wings use the room beside the notch and never cover a menu or an icon. Until then, activities show beneath the camera."
            : "With Accessibility, its wings use the room beside the notch and never cover a menu or an icon. Until then, activities show beneath the camera."
    }
}
