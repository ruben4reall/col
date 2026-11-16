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

    /// The names a result may take, in order: beside `source`, named after it with `suffix` and `fileExtension`, then
    /// with " 2", " 3"… as the Finder does. The tools move their result to the first one still free, never over a file.
    public static func candidate(for source: URL, suffix: String? = nil, fileExtension: String, attempt: Int) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " " + $0 } ?? "")
        let name = attempt <= 1 ? base : "\(base) \(attempt)"
        return source.deletingLastPathComponent().appendingPathComponent(fileExtension.isEmpty ? name : name + "." + fileExtension)
    }

    /// The first of those names that `exists` says is free.
    public static func destination(for source: URL, suffix: String? = nil, fileExtension: String, exists: (URL) -> Bool) -> URL {
        var attempt = 1
        while exists(candidate(for: source, suffix: suffix, fileExtension: fileExtension, attempt: attempt)) { attempt += 1 }
        return candidate(for: source, suffix: suffix, fileExtension: fileExtension, attempt: attempt)
    }

    /// Names for files gathered in one folder, as a .zip of several files gathers them: two files of the same name,
    /// from two folders, become "Notes.txt" and "Notes 2.txt". Case does not count, as on the Mac's disks.
    public static func uniqueNames(_ names: [String]) -> [String] {
        var taken: Set<String> = []
        return names.map { name in
            let url = URL(fileURLWithPath: name)
            var attempt = 1
            var candidate = name
            while taken.contains(candidate.lowercased()) {
                attempt += 1
                candidate = self.candidate(for: url, fileExtension: url.pathExtension, attempt: attempt).lastPathComponent
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }
}
