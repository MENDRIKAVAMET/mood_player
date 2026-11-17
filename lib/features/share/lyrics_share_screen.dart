import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/track.dart';
import '../../services/lyrics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_error.dart';
import '../../widgets/app_header.dart';
import 'excerpt_share_screen.dart';
import 'lyrics_card_screen.dart';

/// Sélection des lignes de paroles à partager, en image (par défaut) ou en
/// texte.
class LyricsShareScreen extends StatefulWidget {
  final Track track;
  final LyricsResult result;

  const LyricsShareScreen({
    super.key,
    required this.track,
    required this.result,
  });

  @override
  State<LyricsShareScreen> createState() => _LyricsShareScreenState();
}

class _LyricsShareScreenState extends State<LyricsShareScreen> {
  late final List<String> _lines = _buildLines(widget.result);
  final Set<int> _selected = <int>{};
  bool _sharing = false;

  static List<String> _buildLines(LyricsResult r) {
    if (r.hasSynced) {
      return r.synced!.map((l) => l.text.trim()).toList();
    }
    return (r.plain ?? '').split('\n').map((l) => l.trimRight()).toList();
  }

  bool _isBlank(int i) => _lines[i].trim().isEmpty;

  void _toggle(int i) {
    if (_isBlank(i)) return;
    setState(() {
      if (!_selected.remove(i)) _selected.add(i);
    });
  }

  void _selectAll() => setState(() {
        _selected
          ..clear()
          ..addAll([
            for (var i = 0; i < _lines.length; i++)
              if (!_isBlank(i)) i,
          ]);
      });

  /// Lignes choisies dans l'ordre, une ligne vide entre deux sélections non
  /// adjacentes (un saut de strophe compte comme non adjacent), puis la
  /// signature « ♪ Titre — Artiste ».
  String _compose() {
    final sorted = _selected.toList()..sort();
    final buf = StringBuffer();
    int? prev;
    for (final i in sorted) {
      if (prev != null) {
        buf.write('\n');
        if (i != prev + 1) buf.write('\n');
      }
      buf.write(_lines[i]);
      prev = i;
    }
    buf.write('\n\n♪ ${widget.track.title} — ${widget.track.artist}');
    return buf.toString();
  }

  /// Lignes choisies dans l'ordre, avec une chaîne vide entre deux sélections
  /// non adjacentes : sert à dessiner la carte image.
  List<String> _blocks() {
    final sorted = _selected.toList()..sort();
    final out = <String>[];
    int? prev;
    for (final i in sorted) {
      if (prev != null && i != prev + 1) out.add('');
      out.add(_lines[i]);
      prev = i;
    }
    return out;
  }

  void _openCard() {
    if (_selected.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LyricsCardScreen(
          track: widget.track,
          lines: _blocks(),
          text: _compose(),
        ),
      ),
    );
  }

  Future<void> _shareText() async {
    if (_sharing || _selected.isEmpty) return;
    setState(() => _sharing = true);
    try {
      await Share.share(_compose());
    } catch (e) {
      if (mounted) {
        showAppError(context, 'Partage impossible. ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Partager des paroles', showBack: true),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        n == 0
                            ? 'Touche les lignes à partager'
                            : '$n ligne${n > 1 ? 's' : ''} choisie${n > 1 ? 's' : ''}',
                        style: AppTheme.bodyMedium
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: _selectAll,
                      child: const Text('Tout sélectionner'),
                    ),
                    TextButton(
                      onPressed:
                          n == 0 ? null : () => setState(_selected.clear),
                      child: const Text('Effacer'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL,
                    vertical: AppTheme.spacingS,
                  ),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) {
                    if (_isBlank(i)) return const SizedBox(height: 14);
                    final on = _selected.contains(i);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: on
                            ? AppTheme.accentPrimary.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusM),
                          onTap: () => _toggle(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingM,
                              vertical: AppTheme.spacingM,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _lines[i],
                                    style: AppTheme.bodyLarge,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spacingS),
                                SizedBox(
                                  width: 24,
                                  child: on
                                      ? Icon(
                                          Icons.check_circle_rounded,
                                          size: 22,
                                          color: AppTheme.accentPrimary,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: n == 0 ? null : _openCard,
                        icon: const Icon(Icons.image_rounded),
                        label: Text('Créer l\'image ($n)'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    TextButton(
                      onPressed: (n == 0 || _sharing) ? null : _shareText,
                      child: const Text('Partager en texte'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ExcerptShareScreen(track: widget.track),
                        ),
                      ),
                      child: const Text('Partager un extrait audio à la place'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
