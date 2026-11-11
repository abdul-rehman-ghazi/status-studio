import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/option_row.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/style/domain/caption_ink.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _swatchSample = 'Aa';
const _swatchFontSize = 18.0;

/// Look (Box / Shadow) and the chosen look's four colours (spec FR-7, M37).
class CaptionAppearanceControls extends StatelessWidget {
  const CaptionAppearanceControls({
    super.key,
    required this.appearance,
    required this.onChanged,
  });

  final CaptionAppearance appearance;
  final ValueChanged<CaptionAppearance> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Look'),
        OptionRow<CaptionLook>(
          options: const [
            (value: CaptionLook.box, label: 'Box'),
            (value: CaptionLook.shadow, label: 'Shadow'),
          ],
          selected: appearance.look,
          onSelected: (look) => onChanged(appearance.copyWith(look: look)),
        ),
        const SizedBox(height: 12),
        const SectionLabel('Colour'),
        Wrap(spacing: 8, runSpacing: 8, children: _swatches()),
      ],
    );
  }

  List<Widget> _swatches() => switch (appearance.look) {
    CaptionLook.box => [
      for (final colours in BoxColours.values)
        _ColourSwatch(
          ink: captionInkFor(CaptionAppearance(boxColours: colours)),
          label: _boxLabel(colours),
          selected: colours == appearance.boxColours,
          onTap: () => onChanged(appearance.copyWith(boxColours: colours)),
        ),
    ],
    CaptionLook.shadow => [
      for (final colours in ShadowColours.values)
        _ColourSwatch(
          ink: captionInkFor(
            CaptionAppearance(look: CaptionLook.shadow, shadowColours: colours),
          ),
          label: _shadowLabel(colours),
          selected: colours == appearance.shadowColours,
          onTap: () => onChanged(appearance.copyWith(shadowColours: colours)),
        ),
    ],
  };
}

String _boxLabel(BoxColours colours) => switch (colours) {
  BoxColours.whiteOnBlack => 'White on black',
  BoxColours.blackOnWhite => 'Black on white',
  BoxColours.yellowOnBlack => 'Yellow on black',
  BoxColours.whiteOnGreen => 'White on green',
};

String _shadowLabel(ShadowColours colours) => switch (colours) {
  ShadowColours.white => 'White',
  ShadowColours.yellow => 'Yellow',
  ShadowColours.blackGlow => 'Black with a light glow',
  ShadowColours.gold => 'Gold',
};

/// The look itself over a picture-like strip, outlined when chosen.
class _ColourSwatch extends StatelessWidget {
  const _ColourSwatch({
    required this.ink,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CaptionInk ink;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColour = selected ? context.palette.accent : Colors.transparent;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColour, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: ReelColors.swatchBackdrop,
            ),
          ),
          alignment: Alignment.center,
          // The swatch is drawn at a fixed size, like the reel itself.
          child: MediaQuery.withNoTextScaling(child: _sample()),
        ),
      ),
    );
  }

  Widget _sample() {
    final text = Text(
      _swatchSample,
      style: TextStyle(
        inherit: false,
        fontFamily: AppFonts.ui,
        fontSize: _swatchFontSize,
        fontWeight: FontWeight.w600,
        color: ink.text,
        shadows: ink.shadowsAt(_swatchFontSize),
      ),
    );
    final box = ink.box;
    if (box == null) {
      return text;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: box,
      child: text,
    );
  }
}
