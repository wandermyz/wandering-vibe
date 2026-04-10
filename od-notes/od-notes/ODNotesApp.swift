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
    @State private var showingFolderPicker = false

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
                        Button {
                            showingFolderPicker = true
                        } label: {
                            Label("Select Folder", systemImage: "folder.badge.plus")
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
                                showingFolderPicker = true
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
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    store.setFolder(url)
                }
            }
        }
    }
}
