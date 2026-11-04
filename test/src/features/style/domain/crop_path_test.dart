import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';

Duration seconds(num value) => Duration(milliseconds: (value * 1000).round());

const left = CropAnchor(x: 0, y: 0.5);
const right = CropAnchor(x: 1, y: 0.5);
const center = CropAnchor(x: 0.5, y: 0.5);

CropPath leftThenRightAtTen({CropArrival arrival = CropArrival.glide}) =>
    CropPath([
      CropKeyframe(time: seconds(0), anchor: left, arrival: CropArrival.glide),
      CropKeyframe(time: seconds(10), anchor: right, arrival: arrival),
    ]);

void main() {
  group('anchorAt', () {
    test('an_empty_path_gives_the_base_anchor', () {
      expect(const CropPath().anchorAt(seconds(3), base: center), center);
    });

    test('before_the_first_keyframe_it_is_the_first_anchor', () {
      final path = CropPath.startingAt(seconds(5), right);

      expect(path.anchorAt(seconds(1), base: left), right);
    });

    test('after_the_last_keyframe_it_holds_the_last_anchor', () {
      expect(leftThenRightAtTen().anchorAt(seconds(20), base: center), right);
    });

    test('a_glide_moves_in_a_straight_line', () {
      expect(
        leftThenRightAtTen().anchorAt(seconds(2.5), base: center).x,
        closeTo(0.25, 1e-9),
      );
    });

    test('a_glide_arrives_at_its_keyframe_time', () {
      expect(leftThenRightAtTen().anchorAt(seconds(10), base: center), right);
    });

    test('a_cut_holds_the_earlier_anchor_until_its_time', () {
      final path = leftThenRightAtTen(arrival: CropArrival.cut);

      expect(path.anchorAt(seconds(9.9), base: center), left);
    });

    test('a_cut_jumps_at_its_time', () {
      final path = leftThenRightAtTen(arrival: CropArrival.cut);

      expect(path.anchorAt(seconds(10), base: center), right);
    });

    test('a_glide_moves_y_too', () {
      final path = CropPath([
        CropKeyframe(
          time: seconds(0),
          anchor: const CropAnchor(x: 0, y: 0),
          arrival: CropArrival.glide,
        ),
        CropKeyframe(
          time: seconds(4),
          anchor: const CropAnchor(x: 0, y: 1),
          arrival: CropArrival.glide,
        ),
      ]);

      expect(path.anchorAt(seconds(1), base: center).y, closeTo(0.25, 1e-9));
    });
  });

  group('withAnchorAt', () {
    test('adds_a_keyframe_that_glides_in', () {
      final path = leftThenRightAtTen().withAnchorAt(seconds(5), center);

      expect(path.keyframes[1].arrival, CropArrival.glide);
    });

    test('keeps_keyframes_in_time_order', () {
      final path = leftThenRightAtTen().withAnchorAt(seconds(5), center);

      expect(path.keyframes.map((keyframe) => keyframe.time), [
        seconds(0),
        seconds(5),
        seconds(10),
      ]);
    });

    test('snaps_the_time_to_a_tenth_of_a_second', () {
      final path = leftThenRightAtTen().withAnchorAt(
        const Duration(milliseconds: 5040),
        center,
      );

      expect(path.keyframes[1].time, seconds(5));
    });

    test('replaces_a_keyframe_within_a_quarter_second', () {
      final path = leftThenRightAtTen().withAnchorAt(seconds(9.8), center);

      expect(path.keyframes.length, 2);
      expect(path.keyframes.last.anchor, center);
    });

    test('a_replaced_keyframe_keeps_how_it_arrives', () {
      final path = leftThenRightAtTen(arrival: CropArrival.cut)
          .withAnchorAt(seconds(9.8), center);

      expect(path.keyframes.last.arrival, CropArrival.cut);
    });

    test('clamps_the_anchor_into_0_to_1', () {
      final path = leftThenRightAtTen().withAnchorAt(
        seconds(5),
        const CropAnchor(x: 1.4, y: -0.2),
      );

      expect(path.keyframes[1].anchor, const CropAnchor(x: 1, y: 0));
    });
  });

  group('withArrival', () {
    test('changes_how_one_keyframe_arrives', () {
      final path = leftThenRightAtTen().withArrival(1, CropArrival.cut);

      expect(path.keyframes[1].arrival, CropArrival.cut);
    });
  });

  group('withoutKeyframe', () {
    test('removes_a_later_keyframe', () {
      expect(leftThenRightAtTen().withoutKeyframe(1).keyframes.length, 1);
    });

    test('refuses_to_remove_the_first_keyframe', () {
      expect(() => leftThenRightAtTen().withoutKeyframe(0), throwsStateError);
    });
  });

  test('startingAt_makes_one_keyframe', () {
    expect(
      CropPath.startingAt(seconds(2), center).keyframes.single.time,
      seconds(2),
    );
  });
}
