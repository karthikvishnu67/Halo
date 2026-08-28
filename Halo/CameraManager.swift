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

    /// The camera's field of view in degrees, read from the active format
    /// rather than assumed — it differs by device and by lens.
    private(set) var fieldOfView: Double = 0

    /// The preview layer reads frames straight from this session.
    nonisolated let session = AVCaptureSession()

    /// Configuring and starting a session blocks, so it never happens on the main thread.
    nonisolated private let sessionQueue = DispatchQueue(label: "com.halo.camera-session")

    /// Camera frames are delivered here, off the main thread.
    nonisolated private let videoQueue = DispatchQueue(label: "com.halo.camera-frames")

    /// Finds people in the frames this session produces.
    let detector: PersonDetector

    @ObservationIgnored nonisolated private let frameForwarder: FrameForwarder

    init() {
        let detector = PersonDetector()
        self.detector = detector
        self.frameForwarder = FrameForwarder { pixelBuffer in
            detector.detect(in: pixelBuffer)
        }
    }

    /// Only touched on `sessionQueue`.
    @ObservationIgnored nonisolated(unsafe) private var isConfigured = false
    @ObservationIgnored nonisolated(unsafe) private var measuredFieldOfView: Double = 0

    func start() async {
        guard await hasPermission() else {
            status = .denied
            return
        }

        let result = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: configureAndStart())
            }
        }

        fieldOfView = result.fieldOfView
        status = result.failure.map { .failed($0) } ?? .running
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

    /// Runs on `sessionQueue`. Reports what went wrong, or nil on success,
    /// along with the camera's field of view.
    nonisolated private func configureAndStart() -> (failure: String?, fieldOfView: Double) {
        var fieldOfView = self.measuredFieldOfView

        if !isConfigured {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else {
                return ("No rear camera available on this device.", 0)
            }
            fieldOfView = Double(camera.activeFormat.videoFieldOfView)
            measuredFieldOfView = fieldOfView

            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: camera)
            } catch {
                return ("Couldn't open the rear camera: \(error.localizedDescription)", 0)
            }

            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return ("Couldn't add the rear camera to the capture session.", 0)
            }
            session.addInput(input)

            // A second output alongside the preview layer: the preview keeps
            // rendering on its own while these frames go to Vision.
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(frameForwarder, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return ("Couldn't add the video output to the capture session.", 0)
            }
            session.addOutput(videoOutput)

            session.commitConfiguration()

            isConfigured = true
        }

        if !session.isRunning { session.startRunning() }
        return (nil, fieldOfView)
    }
}
