import Foundation

enum FileItem: Identifiable, Hashable {
    case folder(url: URL, name: String)
    case note(url: URL, name: String, lastModified: Date?)

    var id: URL {
        switch self {
        case .folder(let url, _): return url
        case .note(let url, _, _): return url
        }
    }

    var name: String {
        switch self {
        case .folder(_, let name): return name
        case .note(_, let name, _): return name
        }
    }

    var url: URL {
        switch self {
        case .folder(let url, _): return url
        case .note(let url, _, _): return url
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}
