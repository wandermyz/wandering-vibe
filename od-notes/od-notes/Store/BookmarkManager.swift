import Foundation

enum BookmarkManager {
    private static let key = "folderBookmark"

    static func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            try? save(url: url)
        }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
