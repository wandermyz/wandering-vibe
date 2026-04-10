import Foundation
import Observation

enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable
class NotesStore {
    var folderURL: URL?

    init() {
        if let url = BookmarkManager.resolve() {
            folderURL = url
        }
    }

    func setFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        try? BookmarkManager.save(url: url)
        folderURL = url
    }

    func changeFolder() {
        BookmarkManager.clear()
        folderURL = nil
    }

    func enumerateDirectory(at url: URL) async -> Result<[FileItem], Error> {
        let root = self.folderURL ?? url
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var items: [FileItem] = []
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDirectory = resourceValues.isDirectory ?? false

                if isDirectory {
                    items.append(.folder(url: itemURL, name: itemURL.lastPathComponent))
                } else if itemURL.pathExtension.lowercased() == "md" {
                    items.append(.note(
                        url: itemURL,
                        name: itemURL.lastPathComponent,
                        lastModified: resourceValues.contentModificationDate
                    ))
                }
            }

            items.sort { a, b in
                if a.isFolder != b.isFolder { return a.isFolder }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            return .success(items)
        } catch {
            return .failure(error)
        }
    }

    func loadContent(at url: URL) async -> Result<String, Error> {
        guard let folderURL else {
            return .failure(NSError(domain: "ODNotes", code: 2, userInfo: [NSLocalizedDescriptionKey: "No folder selected"]))
        }
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return .success(content)
        } catch {
            return .failure(error)
        }
    }

    func saveContent(_ content: String, to url: URL) async -> Error? {
        guard let folderURL else {
            return NSError(domain: "ODNotes", code: 2, userInfo: [NSLocalizedDescriptionKey: "No folder selected"])
        }
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return error
        }
    }
}
