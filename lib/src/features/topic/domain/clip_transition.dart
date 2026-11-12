/// How one cut gives way to the next in the joined clip (spec FR-36,
/// FR-37). One transition for every join.
enum ClipTransition {
  cut('Cut'),
  crossfade('Crossfade'),
  fadeThroughBlack('Fade through black'),
  slide('Slide');

  const ClipTransition(this.label);

  final String label;
}

/// Every transition but Cut takes this long (spec FR-36).
const transitionLength = Duration(milliseconds: 300);
