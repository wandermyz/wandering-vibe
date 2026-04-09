import SwiftUI

struct NoteDetailView: View {
    let file: FileItem
    @Environment(NotesStore.self) private var store
    @State private var content: String = ""
    @State private var editBuffer: String = ""
    @State private var isEditing = false
    @State private var loadingState: LoadingState = .loading
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            Group {
                switch loadingState {
                case .loading:
                    ProgressView("Loading note...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message):
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await loadContent() }
                        }
                    }
                case .loaded:
                    if isEditing {
                        TextEditor(text: $editBuffer)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        MarkdownView(markdown: content)
                    }
                case .idle:
                    EmptyView()
                }
            }

            if isSaving {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Saving...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loadingState == .loaded {
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            Task { await save() }
                        } else {
                            editBuffer = content
                            isEditing = true
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .alert("Save Error", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        loadingState = .loading
        let result = await store.loadContent(at: file.url)
        switch result {
        case .success(let text):
            content = text
            loadingState = .loaded
        case .failure(let error):
            loadingState = .error(error.localizedDescription)
        }
    }

    private func save() async {
        isSaving = true
        if let error = await store.saveContent(editBuffer, to: file.url) {
            saveError = error.localizedDescription
        } else {
            content = editBuffer
            isEditing = false
        }
        isSaving = false
    }
}
