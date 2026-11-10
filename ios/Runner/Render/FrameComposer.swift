import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// A decoded frame, the way it must be turned to be shown upright (the track's preferred
/// transform), and its time into the clip.
struct SourceFrame {
    let pixels: CVPixelBuffer
    let orientation: CGAffineTransform
    let timeMs: Int64
}

/// Draws one output frame: the source frame framed as the spec says (spec §6.3.1, §6.3.2), then
/// the caption line due, or the branding, over it (FR-7a). Used from one queue.
final class FrameComposer {
    private let spec: RenderSpec
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpace(name: CGColorSpace.sRGB)!
    private let outputRect: CGRect
    private let overlays: OverlayImages

    /// Throws when the branding image can't be read, so a bad spec fails the render at once.
    init(spec: RenderSpec) throws {
        self.spec = spec
        outputRect = CGRect(x: 0, y: 0, width: spec.outputWidth, height: spec.outputHeight)
        overlays = OverlayImages(size: outputRect.size)
        _ = try overlays.image(atPath: spec.overlayPath)
    }

    func render(_ source: SourceFrame, into output: CVPixelBuffer) throws {
        let upright = uprightImage(of: source.pixels, transform: source.orientation)
        let path = overlayPathAt(brandingPath: spec.overlayPath, cues: spec.captionCues, timeMs: source.timeMs)
        let overlay = try overlays.image(atPath: path)
        let frame = framed(upright, atMs: source.timeMs).composited(over: CIImage(color: .black).cropped(to: outputRect))
        context.render(overlay.composited(over: frame), to: output, bounds: outputRect, colorSpace: colorSpace)
    }

    /// The decoded frame turned the way the video is shown, with its corner at the origin. Crops
    /// are measured on that picture (Dart's `sourceSize` is the displayed size).
    private func uprightImage(of pixels: CVPixelBuffer, transform: CGAffineTransform) -> CIImage {
        let image = CIImage(cvPixelBuffer: pixels)
        let codedHeight = image.extent.height
        let toTopLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: codedHeight)
        let turned = image.transformed(by: toTopLeft.concatenating(transform))
        let displayHeight = turned.extent.maxY
        let toBottomLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: displayHeight)
        let upright = turned.transformed(by: toBottomLeft)
        return upright.transformed(by: CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY))
    }

    private func framed(_ upright: CIImage, atMs timeMs: Int64) -> CIImage {
        switch spec.fill {
        case .crop(let rect):
            return stretched(upright, crop: rect)
        case .movingCrop(let keyframes):
            return stretched(upright, crop: ndcRectAt(keyframes, timeMs: timeMs))
        case .blur(let sigma, let sharpScaleX, let sharpScaleY):
            return blurred(upright, sigma: sigma, sharpScale: CGSize(width: CGFloat(sharpScaleX), height: CGFloat(sharpScaleY)))
        case .none:
            return fitted(upright)
        }
    }

    /// The crop scaled to fill the output. Crop sizes are rounded to even pixels on the other
    /// platform, so the aspect is a hair off the output's; stretching (under 0.5 %) avoids thin
    /// bars at the edges. The whole frame is scaled and then cut, so the edge pixels keep their
    /// real neighbours.
    private func stretched(_ upright: CIImage, crop: NdcRect) -> CIImage {
        let window = pixelRect(for: crop, in: upright.extent.size)
        let toOutput = CGAffineTransform(translationX: -window.minX, y: -window.minY)
            .concatenating(CGAffineTransform(scaleX: outputRect.width / window.width, y: outputRect.height / window.height))
        return upright.transformed(by: toOutput).cropped(to: outputRect)
    }

    /// A blurred copy of the whole frame stretched over the output, the sharp frame in the middle
    /// at `sharpScale` of the output. The blur is measured in source pixels (spec §6.3.1).
    private func blurred(_ upright: CIImage, sigma: Float, sharpScale: CGSize) -> CIImage {
        let size = upright.extent.size
        let backdrop = upright.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigma))
            .cropped(to: upright.extent)
            .transformed(by: CGAffineTransform(scaleX: outputRect.width / size.width, y: outputRect.height / size.height))
        let sharpWidth = outputRect.width * sharpScale.width
        let sharpHeight = outputRect.height * sharpScale.height
        let sharp = upright
            .transformed(by: CGAffineTransform(scaleX: sharpWidth / size.width, y: sharpHeight / size.height))
            .transformed(by: CGAffineTransform(
                translationX: (outputRect.width - sharpWidth) / 2,
                y: (outputRect.height - sharpHeight) / 2
            ))
        return sharp.composited(over: backdrop).cropped(to: outputRect)
    }

    /// The whole frame, as large as fits the output, in the middle (16:9).
    private func fitted(_ upright: CIImage) -> CIImage {
        let size = upright.extent.size
        let scale = min(outputRect.width / size.width, outputRect.height / size.height)
        return upright
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (outputRect.width - size.width * scale) / 2,
                y: (outputRect.height - size.height * scale) / 2
            ))
            .cropped(to: outputRect)
    }
}

/// Opens the overlay images one at a time as they come due: a reel can have dozens, and each is
/// a full-size frame (spec FR-7a). Used from one queue.
final class OverlayImages {
    private let size: CGSize
    private var shownPath: String?
    private var shown: CIImage?

    init(size: CGSize) {
        self.size = size
    }

    func image(atPath path: String) throws -> CIImage {
        if let shown, path == shownPath { return shown }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw RenderSpecError(message: "Couldn't read the overlay \(path).") }
        let image = CIImage(cgImage: decoded)
        let fitted = image.extent.size == size
            ? image
            : image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height))
        shownPath = path
        shown = fitted
        return fitted
    }
}
