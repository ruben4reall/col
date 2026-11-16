import Foundation

/// The rules behind the shelf's tools: which images they convert, how big a resized image comes out, and the name of
/// what they make, which lands beside the original file and never on top of another one.
public enum ShelfTools {
    public enum ImageFormat: String, CaseIterable, Sendable {
        case png, jpeg, heic

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .heic: "heic"
            }
        }

        /// The Uniform Type Identifier ImageIO writes it with.
        public var typeIdentifier: String {
            switch self {
            case .png: "public.png"
            case .jpeg: "public.jpeg"
            case .heic: "public.heic"
            }
        }

        public var name: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            }
        }

        public init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "png": self = .png
            case "jpg", "jpeg": self = .jpeg
            case "heic", "heif": self = .heic
            default: return nil
            }
        }
    }

    /// File extensions of images the tools can read (ImageIO reads all of them).
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]

    public static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// The formats an image can be converted to: every one but its own.
    public static func conversions(for url: URL) -> [ImageFormat] {
        guard isImage(url) else { return [] }
        let own = ImageFormat(fileExtension: url.pathExtension)
        return ImageFormat.allCases.filter { $0 != own }
    }

    public enum Resize: Equatable, Sendable {
        /// Half the width and the height.
        case half
        /// The size in points of a Retina capture: its pixels over its resolution, so a 144 dpi screenshot halves.
        case pointSize
    }

    /// The pixel size an image comes out at, or nil when the resize would not change it (a capture already at 1x).
    public static func size(_ resize: Resize, width: Int, height: Int, dpi: Double?) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let scale: Double
        switch resize {
        case .half:
            scale = 0.5
        case .pointSize:
            guard let dpi, dpi > 72.5 else { return nil }
            scale = 72 / dpi
        }
        let size = (width: max(1, Int((Double(width) * scale).rounded())), height: max(1, Int((Double(height) * scale).rounded())))
        return size.width == width && size.height == height ? nil : size
    }

    /// Where a result goes: beside `source`, named after it with `suffix` and `fileExtension`. A name already taken
    /// gets " 2", " 3"… as the Finder does.
    public static func destination(for source: URL, suffix: String? = nil, fileExtension: String, exists: (URL) -> Bool) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " " + $0 } ?? "")
        func named(_ name: String) -> URL {
            folder.appendingPathComponent(fileExtension.isEmpty ? name : name + "." + fileExtension)
        }
        var candidate = named(base)
        var number = 2
        while exists(candidate) {
            candidate = named("\(base) \(number)")
            number += 1
        }
        return candidate
    }
}
