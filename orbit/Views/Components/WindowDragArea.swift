import SwiftUI
import AppKit

/// An invisible background view that enables window dragging when clicked
/// Use this as a background on header/title areas to make them draggable
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Custom NSView that allows window dragging
private class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Accept clicks even when window is not key
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Initiate window drag
        window?.performDrag(with: event)
    }
}
