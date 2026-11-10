import CoreMedia
import XCTest

@testable import Runner

/// The same cases as Dart's `crop_path_test.dart` and Android's `MovingCropTest`: the three sides
/// must agree at every boundary. Android's matrix cases become `pixelRect` cases, since the
/// renderer crops with a Core Image rectangle, not a GL matrix.
final class MovingCropTests: XCTestCase {
    private let left = NdcRect(left: -1, right: -0.4, bottom: -1, top: 1)
    private let right = NdcRect(left: 0.4, right: 1, bottom: -1, top: 1)

    private func leftThenRightAtTenSeconds(glide: Bool) -> [CropKeyframe] {
        [
            CropKeyframe(timeMs: 0, glide: true, rect: left),
            CropKeyframe(timeMs: 10_000, glide: glide, rect: right),
        ]
    }

    func test_before_the_first_keyframe_it_is_the_first_rectangle() {
        XCTAssertEqual(ndcRectAt(leftThenRightAtTenSeconds(glide: true), timeMs: -500), left)
    }

    func test_after_the_last_keyframe_it_holds_the_last_rectangle() {
        XCTAssertEqual(ndcRectAt(leftThenRightAtTenSeconds(glide: true), timeMs: 20_000), right)
    }

    func test_a_glide_a_quarter_of_the_way_moves_a_quarter() {
        let rect = ndcRectAt(leftThenRightAtTenSeconds(glide: true), timeMs: 2_500)

        XCTAssertEqual(rect.left, -0.65, accuracy: 1e-5)
    }

    func test_a_glide_arrives_at_its_keyframe_time() {
        XCTAssertEqual(ndcRectAt(leftThenRightAtTenSeconds(glide: true), timeMs: 10_000), right)
    }

    func test_a_cut_holds_the_earlier_rectangle_just_before_its_time() {
        XCTAssertEqual(ndcRectAt(leftThenRightAtTenSeconds(glide: false), timeMs: 9_999), left)
    }

    func test_a_cut_has_jumped_at_exactly_its_time() {
        XCTAssertEqual(ndcRectAt(leftThenRightAtTenSeconds(glide: false), timeMs: 10_000), right)
    }

    func test_the_clip_clock_is_the_presentation_time_in_milliseconds() {
        XCTAssertEqual(clipTimeMs(CMTime(value: 1_500_000, timescale: 1_000_000)), 1_500)
    }

    func test_the_clip_clock_drops_the_part_of_a_millisecond() {
        XCTAssertEqual(clipTimeMs(CMTime(value: 1_999_999, timescale: 1_000_000)), 1_999)
    }

    func test_the_whole_frame_is_every_pixel() {
        let window = pixelRect(for: NdcRect(left: -1, right: 1, bottom: -1, top: 1), in: CGSize(width: 1920, height: 1080))

        XCTAssertEqual(window, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func test_the_left_half_is_the_left_half_of_the_pixels() {
        let window = pixelRect(for: NdcRect(left: -1, right: 0, bottom: -1, top: 1), in: CGSize(width: 1920, height: 1080))

        XCTAssertEqual(window, CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_the_top_of_the_frame_is_the_top_in_core_image_rows() {
        let window = pixelRect(for: NdcRect(left: -1, right: 1, bottom: 0, top: 1), in: CGSize(width: 1920, height: 1080))

        XCTAssertEqual(window.minY, 540)
    }

    func test_a_cue_is_shown_from_its_start() {
        let cues = [CaptionCue(startMs: 1_000, endMs: 2_000, path: "line.png")]

        XCTAssertEqual(overlayPathAt(brandingPath: "brand.png", cues: cues, timeMs: 1_000), "line.png")
    }

    func test_a_cue_has_ended_at_exactly_its_end() {
        let cues = [CaptionCue(startMs: 1_000, endMs: 2_000, path: "line.png")]

        XCTAssertEqual(overlayPathAt(brandingPath: "brand.png", cues: cues, timeMs: 2_000), "brand.png")
    }
}
