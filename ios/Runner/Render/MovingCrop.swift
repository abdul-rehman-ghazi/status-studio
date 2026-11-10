import CoreGraphics
import CoreMedia
import Foundation

/// A crop rectangle in normalised device coordinates (spec §6.3.1): x from -1 (left) to 1
/// (right), y from -1 (bottom) to 1 (top).
struct NdcRect: Equatable {
    let left: Float
    let right: Float
    let bottom: Float
    let top: Float
}

/// The crop at `timeMs` into the clip. `glide` is how this keyframe is reached from the one
/// before it; a cut jumps.
struct CropKeyframe: Equatable {
    let timeMs: Int64
    let glide: Bool
    let rect: NdcRect
}

/// Milliseconds into the clip for a frame's presentation time. The clip is cut out of the video
/// first, so its frames start at zero, and the crop and the caption lines read the same clock
/// and can't drift apart (spec §6.3.2; Android's `clipTimeMs`).
func clipTimeMs(_ presentationTime: CMTime) -> Int64 {
    CMTimeConvertScale(presentationTime, timescale: 1000, method: .roundTowardZero).value
}

/// The crop at `timeMs` (spec §6.3.2), the same rule as Dart's `CropPath.anchorAt` and Android's
/// `ndcRectAt`: before the first keyframe the first rectangle, after the last the last. Between
/// two, a glide moves each edge in a straight line and a cut holds the earlier rectangle until
/// the later keyframe's time, and from that time on is the later one.
func ndcRectAt(_ keyframes: [CropKeyframe], timeMs: Int64) -> NdcRect {
    precondition(!keyframes.isEmpty, "A moving crop needs at least one keyframe.")
    guard let next = keyframes.firstIndex(where: { $0.timeMs > timeMs }) else {
        return keyframes[keyframes.count - 1].rect
    }
    if next == 0 { return keyframes[0].rect }
    let from = keyframes[next - 1]
    let to = keyframes[next]
    if !to.glide { return from.rect }
    let done = Float(timeMs - from.timeMs) / Float(to.timeMs - from.timeMs)
    return NdcRect(
        left: lerp(from.rect.left, to.rect.left, done),
        right: lerp(from.rect.right, to.rect.right, done),
        bottom: lerp(from.rect.bottom, to.rect.bottom, done),
        top: lerp(from.rect.top, to.rect.top, done)
    )
}

private func lerp(_ from: Float, _ to: Float, _ fraction: Float) -> Float {
    from + (to - from) * fraction
}

/// The pixels of a frame of `size` that `rect` covers, in Core Image's coordinates (origin at
/// the bottom left, y up, the same direction as NDC).
func pixelRect(for rect: NdcRect, in size: CGSize) -> CGRect {
    CGRect(
        x: CGFloat((rect.left + 1) / 2) * size.width,
        y: CGFloat((rect.bottom + 1) / 2) * size.height,
        width: CGFloat((rect.right - rect.left) / 2) * size.width,
        height: CGFloat((rect.top - rect.bottom) / 2) * size.height
    )
}
