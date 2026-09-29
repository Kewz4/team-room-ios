import SwiftUI
import UIKit

@MainActor
final class ScrollHandle {
    weak var view: UIScrollView?

    func bottom() {
        guard let view else { return }
        view.layoutIfNeeded()
        let offset = max(-view.adjustedContentInset.top,
                         view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: false)
    }
}

/// Access only this conversation's public UIScrollView to jump to its measured end.
struct ScrollHandleBinder: UIViewRepresentable {
    let handle: ScrollHandle
    let attached: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            var parent = view.superview
            while let current = parent {
                if let scroll = current as? UIScrollView {
                    if handle.view !== scroll { handle.view = scroll; attached() }
                    return
                }
                parent = current.superview
            }
        }
    }
}
