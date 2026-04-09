import SwiftUI

@main
struct ODNotesApp: App {
    @State private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let folderURL = store.folderURL {
                    FolderBrowserView(folderURL: folderURL, title: "Notes")
                } else {
                    ContentUnavailableView {
                        Label("No Folder Selected", systemImage: "folder")
                    } description: {
                        Text("Select a folder from OneDrive or Files to browse your Markdown notes.")
                    } actions: {
                        FolderPickerButton { url in
                            store.setFolder(url)
                        }
                    }
                }
            }
            .navigationDestination(for: FileItem.self) { item in
                switch item {
                case .folder(let url, let name):
                    FolderBrowserView(folderURL: url, title: name)
                case .note:
                    NoteDetailView(file: item)
                }
            }
            .toolbar {
                if store.folderURL != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            FolderPickerButton { url in
                                store.setFolder(url)
                            }
                            Button(role: .destructive) {
                                store.changeFolder()
                            } label: {
                                Label("Disconnect Folder", systemImage: "folder.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
}
