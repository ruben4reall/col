import Foundation

/// A named, saved setup of the menu bar: the drawers and the place of every icon, and the appearance. Switching to a
/// profile puts its setup in place; while it is active, every change of the layout or the appearance is written back
/// into it, so switching away and back finds the menu bar as it was left.
public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var layout: Layout
    public var appearance: Appearance
    /// A shortcut that switches to it.
    public var shortcut: Shortcut?

    /// The longest name.
    public static let maximumNameLength = 40

    public init(id: UUID = UUID(), name: String, layout: Layout, appearance: Appearance, shortcut: Shortcut? = nil) {
        self.id = id
        self.name = name
        self.layout = layout
        self.appearance = appearance
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey { case id, name, layout, appearance, shortcut }

    /// A profile needs its identity and its layout, or it is skipped; the rest falls back to a default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layout = try container.decode(Layout.self, forKey: .layout)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .standard
        shortcut = try? container.decodeIfPresent(Shortcut.self, forKey: .shortcut)
    }

    /// Name trimmed and shortened, drawers and appearance cleaned.
    public var clamped: Profile {
        var copy = self
        copy.name = Self.cleanName(name)
        copy.layout.drawers = layout.drawers.map(\.clamped)
        copy.appearance = appearance.clamped
        return copy
    }

    static func cleanName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
    }
}

extension TiroirSettings {
    public func profile(_ id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// The profile in use, if any.
    public var currentProfile: Profile? {
        activeProfile.flatMap(profile)
    }

    /// Saves the current layout and appearance as a new profile, placed last, and makes it active.
    @discardableResult
    public mutating func saveCurrentAsProfile(named name: String, id: UUID = UUID()) -> UUID {
        writeThrough()
        profiles.append(Profile(id: id, name: Profile.cleanName(name), layout: layout, appearance: appearance))
        activeProfile = id
        return id
    }

    /// Writes the current layout and appearance into the active profile, so that it always holds what the menu bar
    /// shows. Without an active profile, nothing changes.
    public mutating func writeThrough() {
        guard let id = activeProfile, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].layout = layout
        profiles[index].appearance = appearance
    }

    /// Puts a profile's layout and appearance in place and makes it active. The setup being left is written into its
    /// own profile first. An unknown profile changes nothing.
    public mutating func switchProfile(to id: UUID) {
        guard let target = profile(id) else { return }
        writeThrough()
        layout = target.layout
        appearance = target.appearance
        activeProfile = id
    }

    /// Puts a setup back with no profile active: what a trigger brings back when no profile was active before it.
    public mutating func restoreSetup(layout: Layout, appearance: Appearance) {
        writeThrough()
        self.layout = layout
        self.appearance = appearance
        activeProfile = nil
    }

    /// Renames a profile. A name that is empty once trimmed is refused.
    public mutating func renameProfile(_ id: UUID, to name: String) {
        let cleaned = Profile.cleanName(name)
        guard !cleaned.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = cleaned
    }

    /// Copies a profile, right after the original; the copy has no shortcut and is not active. Returns its id.
    @discardableResult
    public mutating func duplicateProfile(_ id: UUID, named name: String, as newID: UUID = UUID()) -> UUID? {
        writeThrough()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = profiles[index]
        copy.id = newID
        copy.name = Profile.cleanName(name)
        copy.shortcut = nil
        profiles.insert(copy, at: index + 1)
        return newID
    }

    /// Deletes a profile. Deleting the active one keeps the current setup and leaves no profile active.
    public mutating func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfile == id { activeProfile = nil }
    }

    /// Moves a profile to a new position among the profiles.
    public mutating func moveProfile(_ id: UUID, to index: Int) {
        guard let from = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles.remove(at: from)
        profiles.insert(profile, at: min(max(index, 0), profiles.count))
    }

    public mutating func setShortcut(_ shortcut: Shortcut?, ofProfile id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].shortcut = shortcut
    }

    /// The first "Profile 1", "Profile 2"… name no profile has yet, from a way of spelling the number.
    public func nextProfileName(_ spell: (Int) -> String) -> String {
        let taken = Set(profiles.map(\.name))
        var number = profiles.count + 1
        while taken.contains(spell(number)) { number += 1 }
        return spell(number)
    }
}
