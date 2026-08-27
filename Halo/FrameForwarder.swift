//
//  FrameForwarder.swift
//  Halo
//
//  Hands camera frames from AVFoundation's delegate callback to a closure.
//

@preconcurrency import AVFoundation
import CoreVideo

/// AVFoundation requires an NSObject delegate, so this is a thin adapter that
/// keeps that requirement out of the rest of the code.
///
/// `nonisolated` because AVFoundation calls the delegate on our video queue,
/// not the main actor — and this project defaults new types to @MainActor.
/// Its only stored property is an immutable Sendable closure, hence @unchecked.
nonisolated final class FrameForwarder: NSObject,
                                        AVCaptureVideoDataOutputSampleBufferDelegate,
                                        @unchecked Sendable {
    private let onFrame: @Sendable (CVPixelBuffer) -> Void

    init(onFrame: @escaping @Sendable (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onFrame(pixelBuffer)
    }
}
