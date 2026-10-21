import 'dart:convert';

import 'package:cm_app/state/game_controller.dart';
import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The device performance gate on a LARGE world: new game wall time, UI
/// responsiveness while the engine isolate advances, and manual save time.
///
/// Budgets are the spec's in profile mode (`flutter drive --profile`); in
/// debug (`flutter test`) they are relaxed since the debug build is several
/// times slower. All numbers are printed as one `[perf] {...}` JSON line.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final frameBudget = Duration(milliseconds: kDebugMode ? 250 : 100);
  final newGameBudget = Duration(seconds: kDebugMode ? 30 : 10);
  final saveBudget = Duration(seconds: kDebugMode ? 5 : 2);

  testWidgets('large world: new game, advance, save', (t) async {
    final l = await loadL10n();
    final store = await tempStore();
    await pumpFreshApp(t, l, store);
    final controller = controllerOf(t);

    final sw = Stopwatch()..start();
    await controller.newGame(
      NewGameSpec(
        seed: 1,
        size: WorldSize.large,
        managerFirstName: 'Perf',
        managerLastName: 'Test',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    final newGameMs = sw.elapsedMilliseconds;
    expect(controller.state, isA<Ready>());
    await t.pumpAndSettle();
    // Flush the engine's frame-timing batch (reported every ~1 s) so the
    // advance window below starts clean.
    await _pumpFor(t, const Duration(milliseconds: 1500));

    // Frames go through the real engine on their own schedule, as in the
    // running app; the test only waits.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final spans = <Duration>[];
    var frames = 0;
    void onTimings(List<FrameTiming> timings) =>
        spans.addAll(timings.map((f) => f.totalSpan));
    void onFrame(Duration _) => frames++;
    binding.addTimingsCallback(onTimings);
    binding.addPersistentFrameCallback(onFrame);

    sw.reset();
    final advance = controller.advance();
    await waitUntil(
      t,
      () => controller.state is! Busy,
      timeout: const Duration(seconds: 60),
      what: 'advance',
    );
    final advanceMs = sw.elapsedMilliseconds;
    final framesDuringAdvance = frames;
    await advance;
    expect(controller.state, isA<Ready>());
    await t.pumpAndSettle();
    await _pumpFor(t, const Duration(milliseconds: 1500));
    binding.removeTimingsCallback(onTimings);
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
    // Persistent frame callbacks cannot be removed; [frames] is just not
    // read any more.

    sw.reset();
    await controller.saveToSlot(1);
    final saveMs = sw.elapsedMilliseconds;
    expect(controller.state, isA<Ready>());

    final maxFrame = spans.fold(Duration.zero, (m, s) => s > m ? s : m);
    debugPrint(
      '[perf] ${jsonEncode({
        'mode': kDebugMode ? 'debug' : (kProfileMode ? 'profile' : 'release'),
        'newGameMs': newGameMs,
        'advanceMs': advanceMs,
        'lastAdvanceMs': controller.lastAdvanceMs,
        'framesDuringAdvance': framesDuringAdvance,
        'timedFrames': spans.length,
        'maxFrameMs': maxFrame.inMilliseconds,
        'saveMs': saveMs,
        'lastSaveMs': controller.lastSaveMs,
        'budgets': {'frameMs': frameBudget.inMilliseconds, 'newGameMs': newGameBudget.inMilliseconds, 'saveMs': saveBudget.inMilliseconds},
      })}',
    );

    expect(newGameMs, lessThan(newGameBudget.inMilliseconds));
    expect(
      framesDuringAdvance,
      greaterThanOrEqualTo(10),
      reason: 'the UI isolate must keep rendering while the engine advances',
    );
    expect(spans, isNotEmpty);
    expect(maxFrame, lessThanOrEqualTo(frameBudget));
    expect(saveMs, lessThan(saveBudget.inMilliseconds));
  });
}

Future<void> _pumpFor(WidgetTester t, Duration d) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < d) {
    await t.pump(const Duration(milliseconds: 50));
  }
}
