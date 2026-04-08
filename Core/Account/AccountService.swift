import Foundation

@MainActor
final class AccountService: ObservableObject {
    @Published private(set) var displayName: String

    private let defaults: UserDefaults
    private let displayNameKey = "scanova.account.displayName"
    private let defaultDisplayName = "My Scanova"

    init() {
        self.defaults = .standard
        let storedName = defaults.string(forKey: displayNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = (storedName?.isEmpty == false ? storedName! : defaultDisplayName)
    }

    func updateDisplayName(_ candidate: String) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? defaultDisplayName : trimmed
        displayName = resolvedName
        defaults.set(resolvedName, forKey: displayNameKey)
    }
}

enum DocumentsSortPreference: String, CaseIterable, Codable {
    case newest
    case oldest
    case name

    var title: String {
        switch self {
        case .newest:
            return "Newest First"
        case .oldest:
            return "Oldest First"
        case .name:
            return "Name"
        }
    }

    var shortTitle: String {
        switch self {
        case .newest:
            return "Newest"
        case .oldest:
            return "Oldest"
        case .name:
            return "Name"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published private(set) var builtInTagDisplayNames: [String: String]
    @Published private(set) var customTags: [String]
    @Published private(set) var defaultDocumentsSort: DocumentsSortPreference
    @Published private(set) var autoOpenScannerOnLaunch: Bool
    @Published private(set) var autoNamingEnabled: Bool

    private let defaults: UserDefaults
    private let builtInTagDisplayNamesKey = "scanova.preferences.tagDisplayNames"
    private let customTagsKey = "scanova.preferences.customTags"
    private let defaultDocumentsSortKey = "scanova.preferences.defaultDocumentsSort"
    private let autoOpenScannerOnLaunchKey = "scanova.preferences.autoOpenScannerOnLaunch"
    private let autoNamingEnabledKey = "scanova.preferences.autoNamingEnabled"

    init() {
        defaults = .standard
        builtInTagDisplayNames = defaults.dictionary(forKey: builtInTagDisplayNamesKey) as? [String: String] ?? [:]
        customTags = defaults.stringArray(forKey: customTagsKey) ?? []
        defaultDocumentsSort = DocumentsSortPreference(rawValue: defaults.string(forKey: defaultDocumentsSortKey) ?? "") ?? .newest
        autoOpenScannerOnLaunch = defaults.object(forKey: autoOpenScannerOnLaunchKey) as? Bool ?? false
        autoNamingEnabled = defaults.object(forKey: autoNamingEnabledKey) as? Bool ?? true
    }

    func displayName(for type: DocumentType) -> String {
        let override = builtInTagDisplayNames[type.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return override?.isEmpty == false ? override! : type.menuTitle
    }

    func updateDisplayName(_ candidate: String, for type: DocumentType) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == type.menuTitle {
            builtInTagDisplayNames.removeValue(forKey: type.rawValue)
        } else {
            builtInTagDisplayNames[type.rawValue] = trimmed
        }
        defaults.set(builtInTagDisplayNames, forKey: builtInTagDisplayNamesKey)
        objectWillChange.send()
    }

    func addCustomTag(_ candidate: String) {
        guard let normalized = normalizedTagName(candidate) else { return }
        guard !customTags.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else { return }
        customTags.append(normalized)
        defaults.set(customTags, forKey: customTagsKey)
    }

    func renameCustomTag(at index: Int, to candidate: String) {
        guard customTags.indices.contains(index), let normalized = normalizedTagName(candidate) else { return }
        guard !customTags.enumerated().contains(where: { $0.offset != index && $0.element.caseInsensitiveCompare(normalized) == .orderedSame }) else { return }
        customTags[index] = normalized
        defaults.set(customTags, forKey: customTagsKey)
    }

    func deleteCustomTags(at offsets: IndexSet) {
        customTags.remove(atOffsets: offsets)
        defaults.set(customTags, forKey: customTagsKey)
    }

    func updateDefaultDocumentsSort(_ value: DocumentsSortPreference) {
        defaultDocumentsSort = value
        defaults.set(value.rawValue, forKey: defaultDocumentsSortKey)
    }

    func setAutoOpenScannerOnLaunch(_ enabled: Bool) {
        autoOpenScannerOnLaunch = enabled
        defaults.set(enabled, forKey: autoOpenScannerOnLaunchKey)
    }

    func setAutoNamingEnabled(_ enabled: Bool) {
        autoNamingEnabled = enabled
        defaults.set(enabled, forKey: autoNamingEnabledKey)
    }

    private func normalizedTagName(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
