import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/branding/presentation/launch_motion.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Tests that drive the whole app turn this off so the splash never sits
/// over the screen under test.
final launchSplashEnabledProvider = Provider<bool>((ref) => true);

/// Plays the launch animation (spec FR-20) over [child], then gets out of
/// the way. [child] is built from the first frame, so Home is ready when the
/// splash fades.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.child});

  final Widget child;

  static const duration = Duration(milliseconds: 1700);
  static const overlayKey = ValueKey('launch-splash');

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LaunchSplash.duration,
  )..addStatusListener(_hideWhenDone);

  var _showing = true;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Reduce motion: skip the splash rather than show a still logo.
    if (MediaQuery.disableAnimationsOf(context)) {
      _showing = false;
      return;
    }
    _controller.forward();
  }

  void _hideWhenDone(AnimationStatus status) {
    if (!status.isCompleted) return;
    setState(() => _showing = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            key: LaunchSplash.overlayKey,
            child: AbsorbPointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    _LaunchFrameView(frame: launchFrameAt(_controller.value)),
              ),
            ),
          ),
      ],
    );
  }
}

class _LaunchFrameView extends StatelessWidget {
  const _LaunchFrameView({required this.frame});

  final LaunchFrame frame;

  /// Matches the native splash's logo, so the hand-over doesn't jump.
  static const _logoSize = 144.0;
  static const _wordmarkGap = 28.0;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: frame.splashOpacity,
      child: ColoredBox(
        color: AppPalette.dark.background,
        child: Stack(
          alignment: Alignment.center,
          children: [_buildLogo(), _buildWordmark()],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Transform.scale(
      scale: frame.logo.scale,
      child: SizedBox.square(
        dimension: _logoSize,
        child: CustomPaint(
          painter: LogoPainter(
            tile: LogoColors.tile,
            ink: LogoColors.ink,
            pose: frame.logo.pose,
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark() {
    return Transform.translate(
      offset: Offset(0, _logoSize / 2 + _wordmarkGap + frame.wordmark.lift),
      child: Opacity(
        opacity: frame.wordmark.opacity,
        child: Text(
          'Status Studio',
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: AppPalette.dark.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
