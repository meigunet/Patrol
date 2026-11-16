import SwiftUI
import UIKit

/// 现场拍照：UIImagePickerController 拍照 + 左下角烧录经纬度与时间水印 + 压缩为 JPEG base64
struct CameraView: UIViewControllerRepresentable {
    var onImage: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (String) -> Void
        let dismiss: () -> Void
        init(onImage: @escaping (String) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage; self.dismiss = dismiss
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let img = info[.originalImage] as? UIImage else { dismiss(); return }
            let watermarked = watermark(img)
            let base64 = compressToBase64(watermarked)
            onImage(base64)
            dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }

        private func watermark(_ image: UIImage) -> UIImage {
            let size = image.size
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                image.draw(in: CGRect(origin: .zero, size: size))
                let loc = LocationService.shared.latestLocation
                let coord: String
                if let c = loc?.coordinate {
                    coord = String(format: "%.6f°N %.6f°E", c.latitude, c.longitude)
                } else { coord = "经纬度未获取" }
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let time = f.string(from: Date())
                let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
                shadow.shadowBlurRadius = 3
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: max(14, size.width / 45)),
                    .foregroundColor: UIColor.white,
                    .shadow: shadow
                ]
                let inset: CGFloat = 12
                (coord as NSString).draw(at: CGPoint(x: inset, y: size.height - 52), withAttributes: attrs)
                (time as NSString).draw(at: CGPoint(x: inset, y: size.height - 28), withAttributes: attrs)
            }
        }

        private func compressToBase64(_ image: UIImage) -> String {
            var scale: CGFloat = 1
            let maxSide: CGFloat = 1280
            if max(image.size.width, image.size.height) > maxSide {
                scale = maxSide / max(image.size.width, image.size.height)
            }
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: target)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            guard let data = resized.jpegData(compressionQuality: 0.8) else { return "" }
            return data.base64EncodedString()
        }
    }
}
