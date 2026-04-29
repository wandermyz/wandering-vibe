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
                        Text("Pick any Markdown file from OneDrive to set its folder as your notes root.")
                    } actions: {
                        Button {
                            presentFolderPicker { url in
                                store.setFolder(url)
                            }
                        } label: {
                            Label("Pick a Note", systemImage: "doc.text")
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
                            Button {
                                presentFolderPicker { url in
                                    store.setFolder(url)
                                }
                            } label: {
                                Label("Change Folder", systemImage: "folder.badge.plus")
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
