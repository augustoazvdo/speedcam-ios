import SwiftUI
import UIKit

/// Shows the composited frames (same pixels as the file, AC-011), aspect-fill with no letterbox (AC-010).
struct PreviewView: UIViewRepresentable {
    let image: CGImage?

    func makeUIView(context: Context) -> PreviewLayerView {
        PreviewLayerView()
    }

    func updateUIView(_ view: PreviewLayerView, context: Context) {
        view.layer.contents = image
    }
}

final class PreviewLayerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        NSNull()
    }
}

/// Isolated so only this view re-renders at the frame rate.
struct LivePreview: View {
    let viewModel: CameraViewModel

    var body: some View {
        PreviewView(image: viewModel.previewImage)
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel(L10n.preview)
            .accessibilityValue(previewValue)
            .accessibilityIdentifier("preview")
    }

    private var previewValue: String {
        let r = viewModel.reading
        return "\(r.display) \(r.unit.label), \(OverlayFormat.gpsLabel(r.gps)), \(L10n.corner(viewModel.selectedCorner))"
    }
}
