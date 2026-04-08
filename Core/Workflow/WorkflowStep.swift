import Foundation

enum WorkflowStep: String, CaseIterable {
    case launch
    case capture
    case export
    case viewer
    case recent
    case selection
}
