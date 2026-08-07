import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mood_player/main.dart';
import 'package:mood_player/providers/providers.dart';

void main() {
  testWidgets('Mood Player smoke test', (WidgetTester tester) async {
    // Override the audio handler provider so the test does not depend on
    // platform channels (audio_service) that are unavailable in tests.
    // The HomeScreen only needs the provider to resolve (or fail) gracefully.
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
    await tester.pump();

    // The app title should be visible.
    expect(find.text('Mood Player'), findsOneWidget);

    // The search bar should be rendered.
    expect(find.text('Rechercher morceaux, artistes...'), findsOneWidget);
  });
}
