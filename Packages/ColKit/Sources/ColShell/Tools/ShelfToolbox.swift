import AppKit
import ColCore
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Vision

/// A word under the shelf's buttons about a tool at work, or its result.
struct ShelfNotice: Equatable {
    var text: String
    var working = false
    var failed = false
}

/// The tools of a file's menu on the shelf: convert or resize an image, compress files into a .zip, copy the text of
/// an image. Everything runs on this Mac, away from the main thread, and what they make lands beside the original and
/// on the shelf.
extension ShelfModel {
    func convert(_ item: Item, to format: ShelfTools.ImageFormat) {
        let source = item.url
        run(String(localized: "Converting…", bundle: .module)) {
            try Self.produce(beside: source, suffix: nil, fileExtension: format.fileExtension) { file in
                try Self.writeImage(from: source, to: file, type: format.typeIdentifier, maxPixelSize: nil, dpi: nil)
            }
        }
    }

    func resize(_ item: Item, _ resize: ShelfTools.Resize) {
        let source = item.url
        run(String(localized: "Resizing…", bundle: .module)) {
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  let size = ShelfTools.size(resize, width: width, height: height, dpi: properties[kCGImagePropertyDPIWidth] as? Double)
            else { throw ShelfToolError.unchanged }
            // Kept in its own format when ImageIO can write it, else PNG.
            let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
            let own = CGImageSourceGetType(image) as String?
            let type = own.flatMap { writable.contains($0) ? $0 : nil } ?? UTType.png.identifier
            let fileExtension = UTType(type)?.preferredFilenameExtension ?? "png"
            let suffix = resize == .half ? "50%" : "1x"
            return try Self.produce(beside: source, suffix: suffix, fileExtension: fileExtension) { file in
                try Self.writeImage(from: source, to: file, type: type, maxPixelSize: max(size.width, size.height), dpi: resize == .pointSize ? 72 : nil)
            }
        }
    }

    /// Compresses files into a .zip with the system's own archiver (the one behind file coordination). One folder
    /// gives "Folder.zip"; a file, or several files, go in a folder of their own inside it, two of the same name
    /// becoming "Notes.txt" and "Notes 2.txt".
    func compress(_ items: [Item]) {
        let urls = items.map(\.url)
        guard let first = urls.first else { return }
        run(String(localized: "Compressing…", bundle: .module)) {
            let manager = FileManager.default
            var isFolder: ObjCBool = false
            let single = urls.count == 1 && manager.fileExists(atPath: first.path, isDirectory: &isFolder) && isFolder.boolValue
            let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : String(localized: "Archive", bundle: .module)
            var scratch: URL?
            defer { if let scratch { try? manager.removeItem(at: scratch) } }
            let archived: URL
            if single {
                archived = first
            } else {
                // Copies on the same volume are clones: instant, and taking no room.
                let folder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: first, create: true)
                scratch = folder
                archived = folder.appendingPathComponent(name)
                try manager.createDirectory(at: archived, withIntermediateDirectories: true)
                for (url, name) in zip(urls, ShelfTools.uniqueNames(urls.map(\.lastPathComponent))) {
                    try manager.copyItem(at: url, to: archived.appendingPathComponent(name))
                }
            }
            let named = first.deletingLastPathComponent().appendingPathComponent(name + ".zip")
            return try Self.produce(beside: named, suffix: nil, fileExtension: "zip") { file in
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: archived, options: .forUploading, error: &coordinationError) { zipped in
                    do { try manager.copyItem(at: zipped, to: file) } catch { copyError = error }
                }
                if let error = coordinationError ?? copyError { throw error }
            }
        }
    }

    /// Reads the text of an image on this Mac and puts it on the clipboard.
    func copyText(_ item: Item) {
        let source = item.url
        setNotice(ShelfNotice(text: String(localized: "Reading the text…", bundle: .module), working: true))
        Task.detached(priority: .userInitiated) {
            let text = Self.recognizeText(in: source)
            await MainActor.run {
                guard let text, !text.isEmpty else {
                    self.setNotice(ShelfNotice(text: String(localized: "No text found", bundle: .module), failed: true), clearing: true)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.setNotice(ShelfNotice(text: String(localized: "Text copied", bundle: .module)), clearing: true)
            }
        }
    }

    // MARK: Running

    private enum ShelfToolError: Error {
        case unchanged
        case unreadable
    }

    /// Runs a tool away from the main thread; its result joins the shelf.
    private func run(_ working: String, _ work: @escaping @Sendable () throws -> URL) {
        setNotice(ShelfNotice(text: working, working: true))
        Task.detached(priority: .userInitiated) {
            let result = Result { try work() }
            await MainActor.run {
                switch result {
                case .success(let url):
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) { self.add([url]) }
                    self.setNotice(ShelfNotice(text: String(localized: "Added to the shelf", bundle: .module)), clearing: true)
                case .failure(ShelfToolError.unchanged):
                    self.setNotice(ShelfNotice(text: String(localized: "Already that size", bundle: .module), failed: true), clearing: true)
                case .failure:
                    self.setNotice(ShelfNotice(text: String(localized: "That did not work", bundle: .module), failed: true), clearing: true)
                }
            }
        }
    }

    private func setNotice(_ notice: ShelfNotice, clearing: Bool = false) {
        noticeClear?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { self.notice = notice }
        guard clearing else { return }
        noticeClear = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.notice = nil }
        }
    }

    // MARK: Files

    /// Makes a result in a scratch folder on the volume where it goes, then moves it beside the original (or into
    /// Col's caches when that folder cannot be written) under the first free name. The move never replaces a file,
    /// even one that appeared in the meantime: a name taken by then passes to the next.
    nonisolated private static func produce(beside source: URL, suffix: String?, fileExtension: String, _ make: (URL) throws -> Void) throws -> URL {
        let manager = FileManager.default
        var base = source
        if !manager.isWritableFile(atPath: source.deletingLastPathComponent().path) {
            let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Col/Shelf", isDirectory: true)
            try manager.createDirectory(at: caches, withIntermediateDirectories: true)
            base = caches.appendingPathComponent(source.lastPathComponent)
        }
        let scratch = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: base.deletingLastPathComponent(), create: true)
        defer { try? manager.removeItem(at: scratch) }
        let made = scratch.appendingPathComponent(fileExtension.isEmpty ? "result" : "result." + fileExtension)
        try make(made)
        for attempt in 1...1000 {
            let target = ShelfTools.candidate(for: base, suffix: suffix, fileExtension: fileExtension, attempt: attempt)
            if renamex_np(made.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }

    /// Writes an image in another format, or smaller, keeping its orientation and colour profile.
    nonisolated private static func writeImage(from source: URL, to destination: URL, type: String, maxPixelSize: Int?, dpi: Double?) throws {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil)
        else { throw ShelfToolError.unreadable }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        if let maxPixelSize {
            guard let resized = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary) else { throw ShelfToolError.unreadable }
            CGImageDestinationAddImage(output, resized, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(output, image, 0, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: destination)
            throw ShelfToolError.unreadable
        }
    }

    /// Vision's text recognition, line by line in reading order; nil when the file is no image.
    nonisolated static func recognizeText(in url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(url: url)
        guard (try? handler.perform([request])) != nil else { return nil }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
