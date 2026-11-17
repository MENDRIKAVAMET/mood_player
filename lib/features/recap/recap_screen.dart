import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/play_log_entry.dart';
import '../../providers/play_log_provider.dart';
import '../../services/recap_builder.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_error.dart';
import '../../widgets/app_header.dart';
import '../../widgets/recap_card.dart';

/// Bilan du mois : une carte-image (ambiance dominante, top morceaux, heure
/// favorite) que l'on peut partager.
class RecapScreen extends ConsumerStatefulWidget {
  const RecapScreen({super.key});

  @override
  ConsumerState<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends ConsumerState<RecapScreen> {
  final GlobalKey _cardKey = GlobalKey();
  DateTime? _selected;
  bool _sharing = false;

  /// Le mois en cours s'il a assez d'écoutes ; sinon le plus récent qui en
  /// a (typiquement le mois dernier, le 1er du mois) ; sinon le mois en cours.
  DateTime _defaultMonth(
    List<PlayLogEntry> log,
    List<DateTime> choices,
    DateTime current,
  ) {
    if (RecapBuilder.build(log, current).hasEnoughData) return current;
    for (final m in choices) {
      if (RecapBuilder.build(log, m).hasEnoughData) return m;
    }
    return current;
  }

  Future<void> _share(MonthlyRecap recap) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('carte indisponible');
      // En debug, toImage échoue si la carte n'a pas encore été peinte.
      if (kDebugMode && boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // 360 x 640 à 3x = 1080 x 1920 px.
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('image vide');

      final dir = await getTemporaryDirectory();
      final mm = recap.month.month.toString().padLeft(2, '0');
      final file = File('${dir.path}/aura_bilan_${recap.month.year}_$mm.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Mon mois en musique, ${RecapBuilder.monthLabel(recap.month)} · Aura',
      );
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
    final log = ref.watch(playLogProvider);
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final withData = RecapBuilder.monthsWithData(log);
    final choices = <DateTime>[
      if (!withData.contains(current)) current,
      ...withData,
    ].take(12).toList();

    final selected = (_selected != null && choices.contains(_selected))
        ? _selected!
        : _defaultMonth(log, choices, current);
    final recap = RecapBuilder.build(log, selected);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Bilan du mois', showBack: true),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL,
                  ),
                  itemCount: choices.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppTheme.spacingS),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text(RecapBuilder.monthLabel(choices[i])),
                    selected: choices[i] == selected,
                    onSelected: (_) => setState(() => _selected = choices[i]),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  child: recap.hasEnoughData
                      ? Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: RepaintBoundary(
                              key: _cardKey,
                              child: RecapCard(recap: recap),
                            ),
                          ),
                        )
                      : _NotEnoughData(
                          plays: recap.totalPlays,
                          logIsEmpty: log.isEmpty,
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingL,
                  0,
                  AppTheme.spacingL,
                  AppTheme.spacingL,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_sharing || !recap.hasEnoughData)
                        ? null
                        : () => _share(recap),
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_rounded),
                    label: const Text('Partager mon bilan'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  final int plays;
  final bool logIsEmpty;

  const _NotEnoughData({required this.plays, required this.logIsEmpty});

  @override
  Widget build(BuildContext context) {
    final message = logIsEmpty
        ? 'Le bilan démarre aujourd\'hui : jusqu\'ici, l\'app ne gardait '
            'pas la date de tes écoutes. Écoute des morceaux jusqu\'au bout '
            'et reviens voir.'
        : 'Il faut au moins ${MonthlyRecap.minPlays} écoutes pour faire un '
            'bilan, tu en es à $plays pour ce mois. Seuls les morceaux '
            'écoutés presque jusqu\'au bout comptent.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_graph_rounded, size: 44, color: AppTheme.textTertiary),
          const SizedBox(height: AppTheme.spacingM),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}
