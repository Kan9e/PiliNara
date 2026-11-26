import 'package:flutter/widgets.dart';

/// Page-local presentation only. The existing player recognizer drives this
/// scope; navigation and in-app PiP still go through the normal PopScope path.
class PlayerSwipeBack extends StatefulWidget {
  const PlayerSwipeBack({
    super.key,
    required this.enabled,
    required this.child,
    this.previewBounds,
    this.miniBounds,
  });

  final bool Function() enabled;
  final Widget child;

  /// Player bounds in page coordinates, when returning can start in-app PiP.
  final Rect? Function()? previewBounds;
  final Rect Function(Size)? miniBounds;

  static PlayerSwipeBackState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SwipeBackScope>()?.state;

  @override
  State<PlayerSwipeBack> createState() => PlayerSwipeBackState();
}

class PlayerSwipeBackState extends State<PlayerSwipeBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  ModalRoute<dynamic>? _route;
  OverlayEntry? _revealedEntry;
  Rect? _playerBounds;
  Rect? _miniBounds;
  bool _hidePage = false;
  bool _wasOpaque = false;
  bool _dragging = false;
  bool _committed = false;
  NavigatorState? _gestureNavigator;

  bool get available =>
      mounted && widget.enabled() && !_offset.isAnimating && !_committed;

  bool begin() {
    if (!available || _dragging) return false;
    final route = ModalRoute.of(context);
    final navigator = route?.navigator;
    if (route == null ||
        navigator == null ||
        !route.isCurrent ||
        route.popDisposition != RoutePopDisposition.pop ||
        route.animation?.status != AnimationStatus.completed ||
        navigator.userGestureInProgress) {
      return false;
    }
    _route = route;
    _playerBounds = widget.previewBounds?.call();
    _miniBounds = widget.miniBounds?.call(MediaQuery.sizeOf(context));
    _dragging = true;
    // Reveal the existing route underneath, without popping or rebuilding a
    // screenshot of it. No global navigation or transition settings change.
    if (route.overlayEntries.isNotEmpty) {
      _revealedEntry = route.overlayEntries.first;
      _wasOpaque = _revealedEntry!.opaque;
      _revealedEntry!.opaque = false;
    }
    _gestureNavigator = navigator..didStartUserGesture();
    return true;
  }

  void update(double distance) {
    if (!_dragging) return;
    if (!widget.enabled() || _route?.isCurrent != true) {
      cancel();
      return;
    }
    _offset.value = distance.clamp(0.0, MediaQuery.sizeOf(context).height);
  }

  Future<void> end(double velocity) async {
    if (!_dragging) return;
    final threshold = (MediaQuery.sizeOf(context).height * 0.12).clamp(
      72.0,
      140.0,
    );
    final dismiss =
        velocity > -300 &&
        (_offset.value >= threshold ||
            (_offset.value >= 24 && velocity >= 800));
    final route = _route!;
    if (!dismiss ||
        !widget.enabled() ||
        !route.isCurrent ||
        route.popDisposition != RoutePopDisposition.pop) {
      cancel();
      return;
    }
    _dragging = false;
    _committed = true;
    final canHandOff =
        _playerBounds != null && widget.previewBounds?.call() != null;
    if (!canHandOff && !MediaQuery.disableAnimationsOf(context)) {
      // Without a mini player, finish the vertical movement before popping.
      try {
        await _offset
            .animateTo(
              MediaQuery.sizeOf(context).height,
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutCubic,
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    _stopGesture();
    if (!mounted) return;
    if (widget.enabled() &&
        route.isCurrent &&
        route.popDisposition == RoutePopDisposition.pop) {
      await route.navigator!.maybePop();
    }
    if (!mounted) return;
    if (route.isActive) {
      _committed = false;
      cancel();
    } else {
      _revealedEntry = null;
      // PiP is inserted at the end of this frame. Hide the page in the same
      // paint as the overlay's first frame, keeping its texture mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hidePage = true);
      });
    }
  }

  void cancel() {
    if (!mounted || _committed) return;
    _dragging = false;
    _offset
        .animateTo(
          0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          _restoreOpacity();
          _stopGesture();
        });
  }

  void _restoreOpacity() {
    if (_route?.isActive == true &&
        _route?.animation?.status == AnimationStatus.completed) {
      _revealedEntry?.opaque = _wasOpaque;
    }
    _revealedEntry = null;
  }

  void _stopGesture() {
    _gestureNavigator?.didStopUserGesture();
    _gestureNavigator = null;
  }

  @override
  void dispose() {
    _restoreOpacity();
    _stopGesture();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SwipeBackScope(
    state: this,
    child: AnimatedBuilder(
      animation: _offset,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final dy = _offset.value;
        final size = MediaQuery.sizeOf(context);
        final player = _playerBounds;
        final transform = Matrix4.identity();
        Rect? clip;
        if (player != null && dy > 0) {
          // Keep the live player mounted. Crop away the recommendations and
          // details as the finger pulls the picture out of its page.
          final target = _miniBounds;
          final travel = ((target?.top ?? size.height) - player.top).clamp(
            size.height * 0.35,
            size.height,
          );
          final progress = (dy / travel).clamp(0.0, 1.0);
          final endScale =
              ((target?.width ?? player.width * 0.45) / player.width).clamp(
                0.0,
                1.0,
              );
          final scale = 1 - (1 - endScale) * progress;
          final dx =
              ((target?.center.dx ?? player.center.dx) - player.center.dx) *
              progress;
          final top = target == null || target.top <= player.top
              ? dy
              : dy.clamp(0.0, target.top - player.top);
          transform
            ..translateByDouble(
              dx + player.center.dx * (1 - scale),
              top + player.top * (1 - scale),
              0,
              1,
            )
            ..scaleByDouble(scale, scale, 1, 1);
          final reveal = Curves.easeOut.transform((dy / 64).clamp(0.0, 1.0));
          clip = Rect.lerp(Offset.zero & size, player, reveal);
        } else {
          transform.translateByDouble(0, dy, 0, 1);
        }
        return Opacity(
          opacity: _hidePage ? 0 : 1,
          child: Transform(
            transform: transform,
            child: ClipRect(clipper: _PlayerClip(clip), child: child),
          ),
        );
      },
    ),
  );
}

class _PlayerClip extends CustomClipper<Rect> {
  const _PlayerClip(this.rect);
  final Rect? rect;
  @override
  Rect getClip(Size size) => rect ?? Offset.zero & size;
  @override
  bool shouldReclip(_PlayerClip oldClipper) => rect != oldClipper.rect;
}

class _SwipeBackScope extends InheritedWidget {
  const _SwipeBackScope({required this.state, required super.child});

  final PlayerSwipeBackState state;

  @override
  bool updateShouldNotify(_SwipeBackScope oldWidget) =>
      state != oldWidget.state;
}
