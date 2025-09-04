import SwiftUI
import UIKit

/// A transparent overlay that enables two-finger panning of the canvas
/// while still allowing all one-finger gestures (tap, drag) to pass through.
/// Recognizes simultaneously with other gestures (so pinch-to-zoom still works).
struct TwoFingerPanGestureView: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isOpaque = false
        v.isUserInteractionEnabled = true
        v.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onChanged: (CGSize) -> Void
        let onEnded: (CGSize) -> Void

        init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (CGSize) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let t = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began, .changed:
                onChanged(CGSize(width: t.x, height: t.y))
            case .ended, .cancelled, .failed:
                onEnded(CGSize(width: t.x, height: t.y))
                recognizer.setTranslation(.zero, in: recognizer.view)
            default:
                break
            }
        }

        // Allow pan to work together with pinch or other gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        // Do not block touches to views beneath this overlay
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            true
        }
    }
}
