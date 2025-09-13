import SwiftUI
import UniformTypeIdentifiers

struct PNGExporter {
    /// Renders any SwiftUI view to a PNG with a solid background and opaque pixels.
    static func renderPNG<V: View>(
        of view: V,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale,
        background: Color = .white,
        colorScheme: ColorScheme = .light
    ) -> Data? {
        // Wrap the content in a solid background and force a stable color scheme
        let content = ZStack {
            background
            view
        }
        .colorScheme(colorScheme)
        .ignoresSafeArea()

        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = true // <<< important: no alpha channel

        #if os(iOS)
        if let ui = renderer.uiImage {
            return ui.pngData()
        }
        #endif

        #if os(macOS)
        if let ns = renderer.nsImage {
            return ns.pngData() // if you have a helper; otherwise convert to PNG here
        }
        #endif

        return nil
    }
}

struct FloorPlanDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { self.data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}
