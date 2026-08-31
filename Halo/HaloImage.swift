//
//  HaloImage.swift
//  Halo
//
//  Getting a picture small enough to be a halo.
//

import UIKit

enum HaloImage {

    /// A halo's picture has to fit through a Bluetooth connection that manages
    /// a few kilobytes a second, so this is sized for the balloon it will be
    /// drawn in rather than for the photo it came from. Anything larger buys
    /// nothing on screen and costs seconds of transfer.
    static let maxDimension: CGFloat = 400
    static let compressionQuality: CGFloat = 0.7

    /// Roughly what a halo should not exceed if it is ever to arrive over the
    /// air in a sensible time.
    static let sensibleByteLimit = 60_000

    static func shrink(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(maxDimension / max(longest, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let shrunk = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return shrunk.jpegData(compressionQuality: compressionQuality)
    }
}

/// Where your halo's picture lives between launches. A file rather than
/// user defaults, which is meant for small values.
enum HaloImageStore {
    private static var url: URL {
        URL.documentsDirectory.appending(path: "my-halo.jpg")
    }

    static func load() -> Data? {
        try? Data(contentsOf: url)
    }

    static func save(_ data: Data?) {
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
