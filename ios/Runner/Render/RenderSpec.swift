import Foundation

/// How the source frame fills the output (spec §6.3.1).
enum Fill: Equatable {
    /// A crop in normalised device coordinates, then scaled to the output.
    case crop(NdcRect)
    /// A crop window that moves over the clip (spec §6.3.2), times counted from the clip start.
    case movingCrop([CropKeyframe])
    /// The whole frame sharp at this share of the output, over a blurred copy.
    case blur(sigma: Float, sharpScaleX: Float, sharpScaleY: Float)
    /// The source framing as it is (16:9).
    case none
}

/// One caption line's overlay image, shown from `startMs` up to `endMs` of the clip.
struct CaptionCue: Equatable {
    let startMs: Int64
    let endMs: Int64
    let path: String
}

/// The overlay image for `timeMs` into the clip: the line due then, else the branding on its
/// own (spec FR-7a). The end of a cue is exclusive, so back-to-back lines never overlap.
func overlayPathAt(brandingPath: String, cues: [CaptionCue], timeMs: Int64) -> String {
    cues.first { timeMs >= $0.startMs && timeMs < $0.endMs }?.path ?? brandingPath
}

struct RenderSpecError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One export, as sent by Dart's `renderSpecFor`.
struct RenderSpec: Equatable {
    let inputPath: String
    let outputPath: String
    let overlayPath: String
    let captionCues: [CaptionCue]
    let clipStartMs: Int64
    let clipEndMs: Int64
    let outputWidth: Int
    let outputHeight: Int
    let fill: Fill
    let videoMimeType: String
    let audioMimeType: String
    /// How long the picture fades in and out; 0 for no fade (spec FR-33).
    let fadeMs: Int64

    /// Throws `RenderSpecError` for a missing or wrong-typed key.
    init(map: [String: Any]) throws {
        inputPath = try map.string("inputPath")
        outputPath = try map.string("outputPath")
        overlayPath = try map.string("overlayPath")
        captionCues = try RenderSpec.cues(from: map)
        clipStartMs = try map.number("clipStartMs").int64Value
        clipEndMs = try map.number("clipEndMs").int64Value
        outputWidth = try map.number("outputWidth").intValue
        outputHeight = try map.number("outputHeight").intValue
        fill = try RenderSpec.fill(from: map)
        videoMimeType = try map.string("videoMimeType")
        audioMimeType = try map.string("audioMimeType")
        // Dart sends it only when the fade is on.
        fadeMs = (map["fadeMs"] as? NSNumber)?.int64Value ?? 0
    }

    private static func fill(from map: [String: Any]) throws -> Fill {
        let fill = try map.string("fill")
        switch fill {
        case "crop":
            if map["cropKeyframes"] != nil { return .movingCrop(try keyframes(from: map)) }
            return .crop(try rect(from: try map.submap("crop")))
        case "blur":
            return .blur(
                sigma: try map.number("blurSigma").floatValue,
                sharpScaleX: try map.number("sharpScaleX").floatValue,
                sharpScaleY: try map.number("sharpScaleY").floatValue
            )
        case "none":
            return Fill.none
        default:
            throw RenderSpecError(message: "Unknown fill '\(fill)'.")
        }
    }

    private static func cues(from map: [String: Any]) throws -> [CaptionCue] {
        guard let entries = map["captionCues"] else { return [] }
        guard let list = entries as? [Any] else {
            throw RenderSpecError(message: "'captionCues' must be a list.")
        }
        return try list.map { entry in
            guard let cue = entry as? [String: Any] else {
                throw RenderSpecError(message: "A caption cue must be a map.")
            }
            return CaptionCue(
                startMs: try cue.number("startMs").int64Value,
                endMs: try cue.number("endMs").int64Value,
                path: try cue.string("path")
            )
        }
    }

    private static func keyframes(from map: [String: Any]) throws -> [CropKeyframe] {
        guard let list = map["cropKeyframes"] as? [Any] else {
            throw RenderSpecError(message: "'cropKeyframes' must be a list.")
        }
        guard !list.isEmpty else { throw RenderSpecError(message: "'cropKeyframes' must not be empty.") }
        return try list.map { entry in
            guard let keyframe = entry as? [String: Any] else {
                throw RenderSpecError(message: "A crop keyframe must be a map.")
            }
            return CropKeyframe(
                timeMs: try keyframe.number("timeMs").int64Value,
                glide: try keyframe.string("arrival") == "glide",
                rect: try rect(from: keyframe)
            )
        }
    }

    private static func rect(from map: [String: Any]) throws -> NdcRect {
        NdcRect(
            left: try map.number("left").floatValue,
            right: try map.number("right").floatValue,
            bottom: try map.number("bottom").floatValue,
            top: try map.number("top").floatValue
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) throws -> String {
        guard let value = self[key] as? String else {
            throw RenderSpecError(message: "'\(key)' must be a string.")
        }
        return value
    }

    // The channel sends Dart ints and doubles as NSNumber.
    func number(_ key: String) throws -> NSNumber {
        guard let value = self[key] as? NSNumber else {
            throw RenderSpecError(message: "'\(key)' must be a number.")
        }
        return value
    }

    func submap(_ key: String) throws -> [String: Any] {
        guard let value = self[key] as? [String: Any] else {
            throw RenderSpecError(message: "'\(key)' must be a map.")
        }
        return value
    }
}
