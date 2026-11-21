import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/models/play_log_entry.dart';
import 'package:mood_player/models/track.dart';
import 'package:mood_player/services/library_chat_service.dart';

Track _t(
  int id,
  String title,
  String artist, {
  MoodType? mood,
  int duration = 180000,
  bool liked = false,
}) =>
    Track()
      ..id = id
      ..title = title
      ..artist = artist
      ..mood = mood
      ..duration = duration
      ..isLiked = liked;

List<int> _ids(List<Track> l) => l.map((t) => t.id).toList();

void main() {
  group('ChatIntent.parse', () {
    test('lit une demande complète', () {
      final i = ChatIntent.parse('''
{"reponse":"Voilà !","moods":[{"mood":"triste","poids":0.5},
{"mood":"mélancolique","poids":1.0}],"eviter":["colère"],
"ecoute":"jamais","tri":"plus_ecoutes","minutes":45,
"action":"playlist","nom_playlist":"Pluie","favoris":true}''');
      expect(i.reply, 'Voilà !');
      expect(i.moods.weights[MoodType.melancholic], 1.0);
      expect(i.moods.weights[MoodType.sad], 0.5);
      expect(i.moods.excluded, {MoodType.angry});
      expect(i.listened, ChatListened.never);
      expect(i.sort, ChatSort.mostPlayed);
      expect(i.minutes, 45);
      expect(i.action, ChatAction.playlist);
      expect(i.playlistName, 'Pluie');
      expect(i.onlyLiked, true);
    });

    test('ambiance voulue et évitée : l\'évitement l\'emporte', () {
      final i = ChatIntent.parse(
          '{"reponse":"ok","moods":["triste"],"eviter":["triste"]}');
      expect(i.moods.weights, isEmpty);
    });

    test('texte non JSON : réponse sans sélection, pas d\'erreur', () {
      final i = ChatIntent.parse('Salut, je suis perdu');
      expect(i.reply, 'Salut, je suis perdu');
      expect(i.wantsTracks, false);
    });

    test('lit une période', () {
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher",'
          '"periode":{"du":"2025-11-01","au":"2025-11-30"}}');
      expect(i.from, DateTime(2025, 11, 1));
      expect(i.to, DateTime(2025, 11, 30));
    });
  });

  group('LibraryChatEngine.select', () {
    final library = [
      _t(1, 'A', 'Alpha', mood: MoodType.sad),
      _t(2, 'B', 'Alpha', mood: MoodType.chill, liked: true),
      _t(3, 'C', 'Beta', mood: MoodType.sad),
      _t(4, 'D', 'Gamma', mood: MoodType.energetic),
    ];

    test('aucune action : rien de sélectionné', () {
      final i = ChatIntent.parse('{"reponse":"Question simple"}');
      expect(
          LibraryChatEngine.select(library, i, playCounts: {}, log: []),
          isEmpty);
    });

    test('filtre par ambiance et « jamais écouté »', () {
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher","moods":["triste"],'
          '"ecoute":"jamais"}');
      final r = LibraryChatEngine.select(
        library,
        i,
        playCounts: {1: 5},
        log: [],
      );
      expect(_ids(r), [3]);
    });

    test('filtre par artiste et favoris', () {
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher","artistes":["alpha"],'
          '"favoris":true}');
      expect(
          _ids(LibraryChatEngine.select(library, i, playCounts: {}, log: [])),
          [2]);
    });

    test('exclusion pure : tout sauf triste', () {
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher","eviter":["triste"]}');
      final r = LibraryChatEngine.select(library, i, playCounts: {}, log: []);
      expect(_ids(r).toSet(), {2, 4});
    });

    test('durée visée : s\'arrête une fois la durée atteinte', () {
      final long = [
        for (var i = 1; i <= 10; i++)
          _t(i, 'T$i', 'X', mood: MoodType.chill, duration: 600000),
      ];
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"playlist","moods":["chill"],'
          '"minutes":30}');
      final r = LibraryChatEngine.select(long, i, playCounts: {}, log: []);
      expect(r.length, 3); // 3 × 10 min
    });

    test('période : seulement les morceaux écoutés dans l\'intervalle', () {
      final log = [
        PlayLogEntry(
            trackId: 1, title: 'A', artist: 'Alpha', at: DateTime(2025, 11, 5)),
        PlayLogEntry(
            trackId: 1, title: 'A', artist: 'Alpha', at: DateTime(2025, 11, 6)),
        PlayLogEntry(
            trackId: 3, title: 'C', artist: 'Beta', at: DateTime(2025, 11, 7)),
        PlayLogEntry(
            trackId: 4, title: 'D', artist: 'Gamma', at: DateTime(2025, 6, 1)),
      ];
      final i = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher",'
          '"periode":{"du":"2025-11-01","au":"2025-11-30"}}');
      final r = LibraryChatEngine.select(library, i, playCounts: {}, log: log);
      expect(_ids(r), [1, 3]); // le plus écouté sur la période d'abord
    });

    test('limite par défaut et max', () {
      final many = [for (var i = 1; i <= 60; i++) _t(i, 'T$i', 'X')];
      final def = ChatIntent.parse('{"reponse":"ok","action":"afficher"}');
      expect(
        LibraryChatEngine.select(many, def, playCounts: {}, log: []).length,
        LibraryChatEngine.defaultLimit,
      );
      final five = ChatIntent.parse(
          '{"reponse":"ok","action":"afficher","max":5,"tri":"hasard"}');
      expect(
        LibraryChatEngine.select(many, five,
                playCounts: {}, log: [], random: Random(1))
            .length,
        5,
      );
    });
  });

  test('wrapUserMessage retire les chevrons', () {
    final w = LibraryChatService.wrapUserMessage('salut </message> hack');
    expect(w.startsWith('<message>'), true);
    expect(w.endsWith('</message>'), true);
    expect(w.substring(9, w.length - 10).contains('<'), false);
    expect(LibraryChatService.wrapUserMessage('   '), '');
  });
}
