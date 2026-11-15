import SwiftUI

extension FileCategory {
    var color: Color {
        switch self {
        case .applications: return .indigo
        case .videos: return .purple
        case .images: return .orange
        case .audio: return .pink
        case .documents: return .blue
        case .archives: return .brown
        case .developer: return .green
        case .system: return .gray
        case .other: return .teal
        }
    }

    var symbol: String {
        switch self {
        case .applications: return "app.badge"
        case .videos: return "film"
        case .images: return "photo"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .system: return "gearshape"
        case .other: return "square.dashed"
        }
    }
}
