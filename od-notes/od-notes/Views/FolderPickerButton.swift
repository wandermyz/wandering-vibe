import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerButton: View {
    let onPick: (URL) -> Void
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Select Folder", systemImage: "folder.badge.plus")
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                onPick(url)
            }
        }
    }
}
