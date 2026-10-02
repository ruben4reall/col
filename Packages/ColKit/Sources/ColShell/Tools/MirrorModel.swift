@preconcurrency import AVFoundation
import Observation

/// The front camera as a mirror. The session runs only while the mirror is on screen.
@MainActor
@Observable
final class MirrorModel {
    private(set) var isRunning = false
    private(set) var denied = false
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "ch.rubencatalao.islet.mirror")
    @ObservationIgnored private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            Task { @MainActor in
                if await AVCaptureDevice.requestAccess(for: .video) { self.run() } else { self.denied = true }
            }
        default:
            denied = true
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = session
        queue.async { session.stopRunning() }
    }

    private func run() {
        denied = false
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .medium
            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            configured = true
        }
        isRunning = true
        let session = session
        queue.async { session.startRunning() }
    }
}
