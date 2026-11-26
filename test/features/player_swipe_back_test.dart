import 'package:PiliPlus/features/player_navigation/player_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<
    ({
      GlobalKey<NavigatorState> nav,
      GlobalKey<PlayerSwipeBackState> swipe,
      MaterialPageRoute<void> route,
    })
  >
  openPlayer(
    WidgetTester tester, {
    bool enabled = true,
    bool canPop = true,
    Widget? child,
    bool nested = false,
    Rect? preview,
  }) async {
    final nav = GlobalKey<NavigatorState>();
    final swipe = GlobalKey<PlayerSwipeBackState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('home')),
      ),
    );
    if (nested) {
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('search')),
        ),
      );
      await tester.pumpAndSettle();
    }
    final route = MaterialPageRoute<void>(
      builder: (_) => PlayerSwipeBack(
        key: swipe,
        enabled: () => enabled,
        previewBounds: () => preview,
        miniBounds: (_) => const Rect.fromLTWH(580, 380, 200, 112),
        child: PopScope(
          canPop: canPop,
          child: child ?? const Scaffold(body: Text('player')),
        ),
      ),
    );
    nav.currentState!.push(route);
    await tester.pumpAndSettle();
    return (nav: nav, swipe: swipe, route: route);
  }

  testWidgets(
    'drag follows finger without rebuilding page; short drag rebounds',
    (tester) async {
      var builds = 0;
      final harness = await openPlayer(
        tester,
        child: Builder(
          builder: (_) {
            builds++;
            return const Scaffold(body: Text('player'));
          },
        ),
      );
      final before = tester.getTopLeft(find.text('player'));
      final initialBuilds = builds;
      final swipe = harness.swipe.currentState!;
      expect(swipe.begin(), isTrue);
      for (var y = 1; y <= 40; y++) {
        swipe.update(y.toDouble());
        await tester.pump();
      }
      expect(tester.getTopLeft(find.text('player')).dy, before.dy + 40);
      expect(builds, initialBuilds);
      expect(harness.route.overlayEntries.first.opaque, isFalse);
      await swipe.end(0);
      await tester.pumpAndSettle();
      expect(harness.route.isCurrent, isTrue);
      expect(harness.route.overlayEntries.first.opaque, isTrue);
      expect(tester.getTopLeft(find.text('player')), before);
      expect(harness.nav.currentState!.userGestureInProgress, isFalse);
    },
  );

  testWidgets('release keeps the mounted player until the route is disposed', (
    tester,
  ) async {
    var mounts = 0;
    final harness = await openPlayer(
      tester,
      preview: const Rect.fromLTWH(0, 0, 320, 180),
      child: _MountCounter(onMount: () => mounts++),
    );
    final swipe = harness.swipe.currentState!;
    expect(mounts, 1);
    expect(swipe.begin(), isTrue);
    swipe.update(160);
    await tester.pump();
    await swipe.end(0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(mounts, 1);
    await tester.pumpAndSettle();
    expect(mounts, 1);
  });

  testWidgets(
    'crop follows the player on a wide layout and hides the outgoing copy on handoff',
    (tester) async {
      const bounds = Rect.fromLTWH(0, 20, 500, 282);
      final harness = await openPlayer(tester, preview: bounds);
      final swipe = harness.swipe.currentState!;
      expect(swipe.begin(), isTrue);
      swipe.update(140);
      await tester.pump();
      final page = find.byKey(harness.swipe);
      final clip = tester
          .widgetList<ClipRect>(
            find.descendant(of: page, matching: find.byType(ClipRect)),
          )
          .first;
      expect(clip.clipper!.getClip(const Size(800, 600)), bounds);
      final box = tester.renderObject(find.byType(Scaffold).last) as RenderBox;
      expect(box.localToGlobal(bounds.topLeft).dy, closeTo(160, 0.01));
      expect(
        box.localToGlobal(bounds.topRight).dx -
            box.localToGlobal(bounds.topLeft).dx,
        lessThan(bounds.width),
      );
      await swipe.end(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: page, matching: find.byType(Opacity)).first,
            )
            .opacity,
        0,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('long drag pops only the top route', (tester) async {
    final harness = await openPlayer(tester, nested: true);
    final swipe = harness.swipe.currentState!;
    expect(swipe.begin(), isTrue);
    swipe.update(160);
    await tester.pump();
    final release = swipe.end(0);
    await tester.pumpAndSettle();
    await release;
    await tester.pumpAndSettle();
    expect(find.text('search'), findsOneWidget);
    expect(find.text('player'), findsNothing);
    expect(harness.nav.currentState!.canPop(), isTrue);
  });

  testWidgets('downward flick dismisses but upward reversal cancels', (
    tester,
  ) async {
    var harness = await openPlayer(tester);
    var swipe = harness.swipe.currentState!;
    expect(swipe.begin(), isTrue);
    swipe.update(30);
    final release = swipe.end(900);
    await tester.pumpAndSettle();
    await release;
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    harness = await openPlayer(tester);
    swipe = harness.swipe.currentState!;
    expect(swipe.begin(), isTrue);
    swipe.update(160);
    await swipe.end(-600);
    await tester.pumpAndSettle();
    expect(harness.route.isCurrent, isTrue);
  });

  testWidgets('setting off and PopScope veto prevent navigation', (
    tester,
  ) async {
    var harness = await openPlayer(tester, enabled: false);
    expect(harness.swipe.currentState!.begin(), isFalse);
    harness = await openPlayer(tester, canPop: false);
    expect(harness.swipe.currentState!.begin(), isFalse);
    expect(harness.route.isCurrent, isTrue);
  });

  testWidgets('cancellation and repeated release never pop a route', (
    tester,
  ) async {
    final harness = await openPlayer(tester);
    final swipe = harness.swipe.currentState!;
    expect(swipe.begin(), isTrue);
    swipe.update(150);
    swipe.cancel();
    await swipe.end(1500);
    await tester.pumpAndSettle();
    expect(harness.route.isCurrent, isTrue);
    expect(harness.nav.currentState!.userGestureInProgress, isFalse);
  });
}

class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('player'));
}
