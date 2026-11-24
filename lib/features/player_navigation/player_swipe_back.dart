import 'package:flutter/widgets.dart';

/// Page-local presentation only. The existing player recognizer drives this
/// scope; navigation and in-app PiP still go through the normal PopScope path.
class PlayerSwipeBack extends StatefulWidget {
  const PlayerSwipeBack({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool Function() enabled;
  final Widget child;

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
    _stopGesture();
    // Keep the release position until PopScope has measured the PiP source.
    // Do not reset the transform before the overlay takes over the texture.
    await route.navigator!.maybePop();
    if (!mounted) return;
    if (route.isCurrent) {
      _committed = false;
      cancel();
    } else {
      _revealedEntry = null;
      setState(() {});
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
        // Keep the same element hierarchy on release: inserting a new wrapper
        // here would unmount and recreate the player during the PiP handoff.
        return FadeTransition(
          opacity: _committed
              ? (_route?.animation ?? kAlwaysCompleteAnimation)
              : kAlwaysCompleteAnimation,
          child: Transform.translate(
            offset: Offset(0, _offset.value),
            child: child,
          ),
        );
      },
    ),
  );
}

class _SwipeBackScope extends InheritedWidget {
  const _SwipeBackScope({required this.state, required super.child});

  final PlayerSwipeBackState state;

  @override
  bool updateShouldNotify(_SwipeBackScope oldWidget) =>
      state != oldWidget.state;
}
