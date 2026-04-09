import SwiftUI

struct FolderBrowserView: View {
    let folderURL: URL
    let title: String
    @Environment(NotesStore.self) private var store
    @State private var items: [FileItem] = []
    @State private var loadingState: LoadingState = .loading

    var body: some View {
        Group {
            switch loadingState {
            case .loading:
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { await loadItems() }
                    }
                }
            case .loaded where items.isEmpty:
                ContentUnavailableView(
                    "No Markdown Files",
                    systemImage: "doc.text",
                    description: Text("This folder contains no .md files or subfolders.")
                )
            case .loaded:
                List(items) { item in
                    switch item {
                    case .folder(let url, let name):
                        NavigationLink(value: item) {
                            Label(name, systemImage: "folder")
                        }
                    case .note(let url, let name, let date):
                        NavigationLink(value: item) {
                            VStack(alignment: .leading) {
                                Text(name)
                                if let date {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await loadItems()
                }
            case .idle:
                EmptyView()
            }
        }
        .navigationTitle(title)
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        loadingState = .loading
        let result = await store.enumerateDirectory(at: folderURL)
        switch result {
        case .success(let fileItems):
            items = fileItems
            loadingState = .loaded
        case .failure(let error):
            loadingState = .error(error.localizedDescription)
        }
    }
}
