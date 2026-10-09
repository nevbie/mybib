import SwiftUI
import UIKit
import PhotosUI

enum ImageTools {
    /// Downscale to `maxEdge` px (longest side) and encode as JPEG.
    static func jpeg(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: quality)
    }

    /// Small cover thumbnail kept with the item (≈ 20–40 KB), as data URL like the web app.
    static func coverDataURL(_ image: UIImage) -> String? {
        jpeg(image, maxEdge: 480, quality: 0.8).map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
    }
}

/// UIImagePickerController with the camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {
        context.coordinator.onDone = onDone
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onDone: (UIImage?) -> Void

        init(onDone: @escaping (UIImage?) -> Void) {
            self.onDone = onDone
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
        }
    }
}

/// Camera (full screen) and photo library (PhotosPicker) behind two flags; hands over the chosen images.
struct PhotoInput: ViewModifier {
    @Binding var camera: Bool
    @Binding var library: Bool
    /// nil = as many as you like
    var maxCount: Int? = 1
    let onImages: ([UIImage]) -> Void
    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $camera) {
                if CameraPicker.available {
                    CameraPicker { img in
                        camera = false
                        if let img { onImages([img]) }
                    }
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Button("OK") { camera = false }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .photosPicker(isPresented: $library, selection: $picked, maxSelectionCount: maxCount, matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { @MainActor in
                    var images: [UIImage] = []
                    for it in items {
                        if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            images.append(img)
                        }
                    }
                    if !images.isEmpty { onImages(images) }
                }
            }
    }
}

extension View {
    func photoInput(camera: Binding<Bool>, library: Binding<Bool>, maxCount: Int? = 1, onImages: @escaping ([UIImage]) -> Void) -> some View {
        modifier(PhotoInput(camera: camera, library: library, maxCount: maxCount, onImages: onImages))
    }
}
