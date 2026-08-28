//
//  CameraPreview.swift
//  Halo
//
//  Bridges AVCaptureVideoPreviewLayer into SwiftUI.
//

import AVFoundation
import SwiftUI
import UIKit

/// A UIView whose backing layer *is* the preview layer, so it resizes with the view for free.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// Lets SwiftUI reach the preview layer for coordinate conversion.
///
/// The preview crops the camera image to fill the screen, so normalized Vision
/// coordinates can't be mapped onto the view by simple multiplication. Only the
/// preview layer knows the crop, and `layerRectConverted` applies it.
@MainActor
final class PreviewLayerHandle {
    fileprivate weak var layer: AVCaptureVideoPreviewLayer?

    /// `rect` is normalized 0-1 with a top-left origin, in the upright
    /// portrait space Vision reports.
    ///
    /// AVFoundation's "metadata output" space is defined in the camera
    /// sensor's own landscape orientation, and `layerRectConverted` rotates it
    /// into portrait itself. Passing an already-upright rect therefore rotates
    /// twice, which put every box to the right of the person and too short.
    /// Rotating back to sensor space first cancels that out.
    func viewRect(for rect: CGRect) -> CGRect? {
        let sensorSpace = CGRect(x: rect.minY,
                                 y: 1 - rect.maxX,
                                 width: rect.height,
                                 height: rect.width)
        return layer?.layerRectConverted(fromMetadataOutputRect: sensorSpace)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let handle: PreviewLayerHandle

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // V1.1 assumes a portrait phone. Rotation handling comes later if we need it.
        view.previewLayer.connection?.videoRotationAngle = 90
        handle.layer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
