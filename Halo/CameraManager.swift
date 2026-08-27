//
//  CameraManager.swift
//  Halo
//
//  Owns the rear-camera capture session: permission, configuration, start/stop.
//

// AVFoundation isn't Sendable-annotated yet; @preconcurrency keeps its
// concurrency warnings out of our build while we use it from a serial queue.
@preconcurrency import AVFoundation
import Observation

@MainActor
@Observable
final class CameraManager {

    /// What the UI should currently show.
    enum Status: Equatable {
        case idle
        case running
        case denied
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// The preview layer reads frames straight from this session.
    nonisolated let session = AVCaptureSession()

    /// Configuring and starting a session blocks, so it never happens on the main thread.
    nonisolated private let sessionQueue = DispatchQueue(label: "com.halo.camera-session")

    /// Only touched on `sessionQueue`.
    @ObservationIgnored nonisolated(unsafe) private var isConfigured = false

    func start() async {
        guard await hasPermission() else {
            status = .denied
            return
        }

        let failure: String? = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: configureAndStart())
            }
        }

        status = failure.map { .failed($0) } ?? .running
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func hasPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Runs on `sessionQueue`. Returns a message describing what went wrong, or nil on success.
    nonisolated private func configureAndStart() -> String? {
        if !isConfigured {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else {
                return "No rear camera available on this device."
            }

            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: camera)
            } catch {
                return "Couldn't open the rear camera: \(error.localizedDescription)"
            }

            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return "Couldn't add the rear camera to the capture session."
            }
            session.addInput(input)
            session.commitConfiguration()

            isConfigured = true
        }

        if !session.isRunning { session.startRunning() }
        return nil
    }
}
