import Foundation

struct SelectionState: Equatable, Codable {
    var isMultiPageSelectionActive: Bool = false
    var selectedPages: Set<Int> = []

    var hasSelection: Bool {
        !selectedPages.isEmpty
    }

    mutating func reset() {
        isMultiPageSelectionActive = false
        selectedPages.removeAll()
    }
}
