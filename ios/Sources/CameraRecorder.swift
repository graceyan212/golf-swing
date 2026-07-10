import SwiftUI
import UIKit

/// The Simulator reports `isSourceTypeAvailable(.camera) == true` on recent Xcode but has no
/// working camera — presenting it hangs on a black screen. Gate on the build environment too.
var cameraAvailable: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    return UIImagePickerController.isSourceTypeAvailable(.camera)
    #endif
}

/// Thin wrapper over UIImagePickerController for recording a swing (physical device only —
/// simulators have no camera; use the photo picker or the demo clip there).
struct CameraRecorder: UIViewControllerRepresentable {
    var onVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if cameraAvailable {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        } else {
            picker.sourceType = .photoLibrary   // never present a broken camera view (e.g. Simulator)
        }
        picker.mediaTypes = ["public.movie"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraRecorder
        init(_ parent: CameraRecorder) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { parent.onVideo(url) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
