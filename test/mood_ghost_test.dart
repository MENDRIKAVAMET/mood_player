import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/models/user_profile.dart';
import 'package:mood_player/widgets/mood_ghost.dart';

void main() {
  group('GhostLook', () {
    test('chaque ambiance (et l\'absence d\'ambiance) a une expression', () {
      for (final mood in [null, ...MoodType.values]) {
        final look = GhostLook.forMood(mood);
        expect(look.phrase.trim(), isNotEmpty, reason: '$mood');
        // Le flottement doit se raccorder à la boucle de 12 s.
        expect(12 % look.bobSeconds, 0, reason: '$mood');
        expect(look.bobAmplitude, greaterThan(0), reason: '$mood');
      }
    });

    test('expressions marquantes', () {
      expect(GhostLook.forMood(MoodType.romantic).eyes, GhostEyes.hearts);
      expect(GhostLook.forMood(MoodType.angry).brows, GhostBrows.angry);
      expect(GhostLook.forMood(MoodType.sad).extra, GhostExtra.tear);
      expect(GhostLook.forMood(MoodType.sleep).extra, GhostExtra.zzz);
      expect(GhostLook.forMood(MoodType.roadtrip).eyes, GhostEyes.sunglasses);
      expect(GhostLook.forMood(MoodType.funny).mouth, GhostMouth.tongue);
      expect(GhostLook.forMood(null).eyes, GhostEyes.dots);
    });
  });

  group('MoodGhost', () {
    Widget host(MoodType? mood, bool playing) => MaterialApp(
          home: Scaffold(
            body: Center(child: MoodGhost(mood: mood, playing: playing)),
          ),
        );

    testWidgets('se dessine pour toutes les ambiances, lecture et pause',
        (tester) async {
      for (final mood in [null, ...MoodType.values]) {
        for (final playing in [true, false]) {
          await tester.pumpWidget(host(mood, playing));
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.takeException(), isNull, reason: '$mood $playing');
        }
      }
    });

    testWidgets('un tap affiche la phrase puis la cache', (tester) async {
      await tester.pumpWidget(host(MoodType.funny, true));
      expect(find.text('Hihi !'), findsNothing);

      await tester.tap(find.byType(MoodGhost));
      await tester.pump();
      expect(find.text('Hihi !'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Hihi !'), findsNothing);
    });

    testWidgets('changer d\'ambiance ne plante pas', (tester) async {
      await tester.pumpWidget(host(MoodType.chill, true));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(host(MoodType.angry, true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });

  group('UserProfile.ghostEnabled', () {
    test('actif par défaut, y compris pour un ancien profil', () {
      expect(const UserProfile.empty().ghostEnabled, true);
      expect(UserProfile.fromJson(const {}).ghostEnabled, true);
    });

    test('aller-retour JSON', () {
      final off = const UserProfile().copyWith(ghostEnabled: false);
      expect(UserProfile.fromJson(off.toJson()).ghostEnabled, false);
    });
  });
}
