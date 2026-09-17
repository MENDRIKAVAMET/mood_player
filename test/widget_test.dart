import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mood_player/main.dart';
import 'package:mood_player/providers/providers.dart';

void main() {
  testWidgets('Mood Player smoke test', (WidgetTester tester) async {
    // Override the audio handler provider so the test does not depend on
    // platform channels (audio_service) that are unavailable in tests.
    // The first tab only needs the provider to resolve (or fail) gracefully.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWith((ref) async {
            throw UnimplementedError('Audio service is not available in tests');
          }),
        ],
        child: const MyApp(),
      ),
    );
    // Pump forward enough to let the one-shot flutter_animate entrance
    // animations (fadeIn/scale, etc.) finish and their internal timers
    // complete before the test tears down the widget tree. A single
    // `pump()` leaves those timers pending, which makes the test binding
    // fail with "A Timer is still pending even after the widget tree was
    // disposed."
    //
    // We can't use `pumpAndSettle()` here because the loading state renders
    // a `Shimmer` skeleton loader, whose animation repeats forever and would
    // make `pumpAndSettle()` time out. Instead, pump a fixed number of
    // frames covering the longest entrance-animation duration used in the
    // app (see AppTheme.animSlow and the explicit delays in library_screen.dart).
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The app title should be visible.
    expect(find.text('Mood Player'), findsOneWidget);

    // The search bar should be rendered.
    expect(find.text('Rechercher morceaux, artistes...'), findsOneWidget);
  });
}
