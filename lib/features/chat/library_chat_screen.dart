import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/play_log_provider.dart';
import '../../providers/playback_stats_provider.dart';
import '../../providers/track_provider.dart';
import '../../services/groq_service.dart';
import '../../services/library_chat_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/track_artwork.dart';

final libraryChatServiceProvider = Provider<LibraryChatService>((ref) {
  return LibraryChatService(ref.watch(groqServiceProvider));
});

class _Msg {
  final bool fromUser;
  final String text;
  final List<Track> tracks;
  final ChatIntent? intent;
  final bool isError;
  final bool loading;

  const _Msg({
    required this.fromUser,
    this.text = '',
    this.tracks = const [],
    this.intent,
    this.isError = false,
    this.loading = false,
  });
}

/// Chat avec la bibliothèque : l'utilisateur écrit en langage naturel, le
/// modèle traduit en critères, l'app sélectionne les morceaux en local et
/// propose de les lire, de les mettre en file ou d'en faire une playlist.
class LibraryChatScreen extends ConsumerStatefulWidget {
  const LibraryChatScreen({super.key});

  @override
  ConsumerState<LibraryChatScreen> createState() => _LibraryChatScreenState();
}

class _LibraryChatScreenState extends ConsumerState<LibraryChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];
  final List<ChatTurn> _history = [];
  bool _sending = false;

  static const _suggestions = [
    'Une playlist de 45 min pour un trajet sous la pluie',
    'Le morceau le plus triste que je n\'ai jamais écouté',
    'Qu\'est-ce que j\'écoutais l\'an dernier à cette période ?',
    'Combien de morceaux par ambiance ?',
    'Un truc énergique, sans colère',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _reset() {
    if (_sending) return;
    setState(() {
      _messages.clear();
      _history.clear();
    });
  }

  String _errorText(Object e) {
    if (e is GroqRateLimitException) {
      final s = e.retryAfter.inSeconds;
      return 'Trop de demandes d\'un coup. Réessaie dans '
          '${s > 0 ? '$s s' : 'quelques secondes'}.';
    }
    if (e is GroqNetworkException) {
      return 'Pas de connexion au service. Vérifie ton réseau et réessaie.';
    }
    if (e is GroqServiceException) {
      return 'Le service n\'a pas répondu correctement. Réessaie dans un '
          'instant.';
    }
    return 'Quelque chose s\'est mal passé. Réessaie.';
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    final wrapped = LibraryChatService.wrapUserMessage(text);
    if (wrapped.isEmpty) return;

    _controller.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _messages
        ..add(_Msg(fromUser: true, text: text))
        ..add(const _Msg(fromUser: false, loading: true));
      _sending = true;
    });
    _scrollToEnd();

    _Msg answer;
    try {
      final tracks = ref.read(trackProvider).tracks;
      final counts = ref.read(playbackStatsProvider);
      final log = ref.read(playLogProvider);
      final digest = LibraryDigest.build(tracks, counts, log);

      final intent = await ref.read(libraryChatServiceProvider).ask(
            digest: digest,
            history: List.unmodifiable(_history),
            message: text,
          );
      final selected = LibraryChatEngine.select(
        tracks,
        intent,
        playCounts: counts,
        log: log,
      );

      _history
        ..add(ChatTurn('user', wrapped))
        ..add(ChatTurn('assistant', intent.raw));

      var reply = intent.reply;
      if (reply.isEmpty) {
        reply = intent.wantsTracks
            ? 'Voilà ce que j\'ai trouvé.'
            : 'Je n\'ai pas bien compris, tu peux reformuler ?';
      }
      if (intent.wantsTracks && selected.isEmpty) {
        final classified = tracks.where((t) => t.isClassified).length;
        reply += classified == 0
            ? '\n\nMais aucun de tes morceaux n\'est encore classé par '
                'ambiance : lance d\'abord la classification.'
            : '\n\nMais aucun morceau ne correspond à ces critères.';
      }
      answer = _Msg(
        fromUser: false,
        text: reply,
        tracks: selected,
        intent: intent,
      );

      if (intent.action == ChatAction.play && selected.isNotEmpty) {
        try {
          final handler = ref.read(audioHandlerProvider).valueOrNull;
          await handler?.playTrackFromList(selected, 0);
        } catch (_) {
          // La carte reste là : l'utilisateur peut lancer la lecture lui-même.
        }
      }
    } catch (e) {
      answer = _Msg(fromUser: false, text: _errorText(e), isError: true);
    }

    if (!mounted) return;
    setState(() {
      _messages.removeLast(); // l'indicateur « je réfléchis »
      _messages.add(answer);
      _sending = false;
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: 'Discuter avec ma bibliothèque',
                showBack: true,
                actions: [
                  if (_messages.isNotEmpty)
                    AppHeaderButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Nouvelle conversation',
                      onTap: _sending ? null : _reset,
                    ),
                ],
              ),
              Expanded(
                child: _messages.isEmpty ? _buildIntro() : _buildMessages(),
              ),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingXL),
      children: [
        const SizedBox(height: AppTheme.spacingL),
        Icon(Icons.chat_bubble_outline_rounded,
            size: 48, color: AppTheme.accentPrimary),
        const SizedBox(height: AppTheme.spacingM),
        Text('Parle à ta musique',
            style: AppTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppTheme.spacingS),
        Text(
          'Demande une playlist, retrouve un morceau, ou pose une question '
          'sur ta bibliothèque. Les morceaux sont choisis dans ta musique, '
          'sur ton téléphone.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingXL),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              onTap: () => _send(s),
              child: Container(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                decoration: AppTheme.glassDecoration,
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: AppTheme.accentPrimary),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(child: Text(s, style: AppTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppTheme.spacingL),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildMessage(_messages[i]),
    );
  }

  Widget _buildMessage(_Msg m) {
    final maxWidth = MediaQuery.of(context).size.width * 0.86;

    if (m.loading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: AppTheme.glassDecoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppTheme.spacingS),
              Text('Je réfléchis…',
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingL,
            vertical: AppTheme.spacingM,
          ),
          decoration: BoxDecoration(
            color: AppTheme.accentPrimary.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: Text(m.text, style: AppTheme.bodyLarge),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: AppTheme.glassDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.text,
              style: AppTheme.bodyLarge.copyWith(
                color: m.isError ? AppTheme.accentError : null,
              ),
            ),
            if (m.tracks.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingM),
              _TracksCard(tracks: m.tracks, intent: m.intent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingS,
        AppTheme.spacingS,
        AppTheme.spacingM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              style: AppTheme.bodyLarge,
              minLines: 1,
              maxLines: 4,
              maxLength: 300,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Écris ta demande…',
                counterText: '',
                hintStyle: AppTheme.bodyLarge
                    .copyWith(color: AppTheme.textTertiary),
                filled: true,
                fillColor: AppTheme.backgroundPrimary,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingL,
                  vertical: AppTheme.spacingM,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingS),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: Icon(Icons.send_rounded, color: AppTheme.accentPrimary),
            tooltip: 'Envoyer',
          ),
        ],
      ),
    );
  }
}

/// Carte de résultats sous une réponse : aperçu des morceaux et actions.
class _TracksCard extends ConsumerWidget {
  final List<Track> tracks;
  final ChatIntent? intent;

  const _TracksCard({required this.tracks, this.intent});

  static const int _preview = 6;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.backgroundCardElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addToQueue(BuildContext context, WidgetRef ref) async {
    final handler = ref.read(audioHandlerProvider).valueOrNull;
    if (handler == null) return;
    await handler.addTracksToQueue(tracks);
    if (context.mounted) {
      _snack(context, '${tracks.length} morceaux ajoutés à la file d\'attente');
    }
  }

  Future<void> _savePlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: intent?.playlistName ?? 'Ma sélection',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: Text('Sauvegarder en playlist', style: AppTheme.titleMedium),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: AppTheme.bodyLarge,
          decoration: const InputDecoration(hintText: 'Nom de la playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final now = DateTime.now();
      final playlist = Playlist()
        ..name = name
        ..trackIds = [for (final t in tracks) t.id]
        ..createdAt = now
        ..updatedAt = now;
      await ref.read(storageServiceProvider).savePlaylist(playlist);
      if (context.mounted) _snack(context, 'Playlist « $name » sauvegardée');
    } catch (_) {
      if (context.mounted) _snack(context, 'Sauvegarde impossible');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = tracks.take(_preview).toList();
    final rest = tracks.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tracks.length} morceau${tracks.length > 1 ? 'x' : ''} · '
          '${LibraryChatEngine.formatTotalDuration(tracks)}',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.spacingS),
        for (final t in shown)
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            onTap: () => openPlayer(context, track: t, tracks: tracks),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
              child: Row(
                children: [
                  TrackArtwork(track: t, size: 40, radius: AppTheme.radiusS),
                  const SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: AppTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          t.artist,
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    t.durationFormatted,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingXS),
            child: Text(
              '+ $rest autre${rest > 1 ? 's' : ''}',
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingS,
          children: [
            ActionChip(
              avatar: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Lire'),
              onPressed: () => playAll(context, tracks),
            ),
            ActionChip(
              avatar: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text('Aléatoire'),
              onPressed: () => playShuffled(context, tracks),
            ),
            ActionChip(
              avatar: const Icon(Icons.queue_music_rounded, size: 18),
              label: const Text('File'),
              onPressed: () => _addToQueue(context, ref),
            ),
            ActionChip(
              avatar: const Icon(Icons.library_add_rounded, size: 18),
              label: const Text('Playlist'),
              onPressed: () => _savePlaylist(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
