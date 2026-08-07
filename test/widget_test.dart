import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mood_player/main.dart';

void main() {
  testWidgets('Mood Player smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();

    // The app title should be visible.
    expect(find.text('Mood Player'), findsOneWidget);

    // The search bar should be rendered.
    expect(find.text('Rechercher morceaux, artistes...'), findsOneWidget);
  });
}
