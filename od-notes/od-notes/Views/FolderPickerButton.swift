import SwiftUI
import UniformTypeIdentifiers

class FolderPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    var onPick: ((URL) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        print("[FolderPicker] didPickDocumentsAt: \(url)")
        onPick?(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("[FolderPicker] cancelled")
    }
}

/// Present the folder picker. Uses multi-select mode so folders can be
/// selected (checkmarked) instead of tapped-to-navigate.
func presentFolderPicker(onPick: @escaping (URL) -> Void) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else {
        print("[FolderPicker] No root VC found")
        return
    }

    var topVC = rootVC
    while let presented = topVC.presentedViewController {
        topVC = presented
    }

    let coordinator = FolderPickerCoordinator()
    coordinator.onPick = onPick

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = coordinator
    picker.allowsMultipleSelection = true

    // Prevent coordinator from being deallocated while picker is shown
    objc_setAssociatedObject(picker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    print("[FolderPicker] Presenting picker from \(type(of: topVC))")
    topVC.present(picker, animated: true)
}
