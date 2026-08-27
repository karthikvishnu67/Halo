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

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // V1.1 assumes a portrait phone. Rotation handling comes later if we need it.
        view.previewLayer.connection?.videoRotationAngle = 90
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
