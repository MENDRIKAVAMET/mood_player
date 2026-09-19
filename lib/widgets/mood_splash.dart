import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Écran d'ambiance affiché pendant une attente un peu longue (le scan de
/// toute la bibliothèque au premier lancement, typiquement) : l'icône puis
/// le nom de l'app puis l'accroche apparaissent en fondu/glissement doux,
/// l'un après l'autre. Volontairement rien qui tourne ni qui rebondit -
/// juste une entrée posée et, une fois en place, une lente respiration
/// derrière l'icône pour que l'écran reste vivant sans jamais ressembler
/// à un loader générique.
class MoodSplash extends StatefulWidget {
  /// Petite ligne de statut optionnelle, sous l'accroche (ex: "Analyse de
  /// votre bibliothèque…").
  final String? caption;

  const MoodSplash({super.key, this.caption});

  @override
  State<MoodSplash> createState() => _MoodSplashState();
}

class _MoodSplashState extends State<MoodSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _breathController,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_breathController.value);
                final glow = 0.16 + t * 0.16;
                final scale = 1.0 + t * 0.025;
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentPrimary.withValues(alpha: glow),
                        blurRadius: 64,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 104,
                  height: 104,
                ),
              ),
            ).animate().fadeIn(
                  duration: AppTheme.animVerySlow,
                  curve: Curves.easeOutCubic,
                ).scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1, 1),
                  duration: AppTheme.animVerySlow,
                  curve: Curves.easeOutCubic,
                ),
            const SizedBox(height: AppTheme.spacingXL),
            Text(
              'Mood Player',
              style: AppTheme.headlineLarge,
              textAlign: TextAlign.center,
            ).animate().fadeIn(
                  duration: AppTheme.animVerySlow,
                  delay: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                ).slideY(
                  begin: 0.3,
                  end: 0,
                  duration: AppTheme.animVerySlow,
                  delay: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Elle sait ce que vous ressentez.',
              style: AppTheme.bodyLarge.copyWith(
                color: AppTheme.textSecondary,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(
                  duration: AppTheme.animVerySlow,
                  delay: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                ).slideY(
                  begin: 0.3,
                  end: 0,
                  duration: AppTheme.animVerySlow,
                  delay: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                ),
            if (widget.caption != null) ...[
              const SizedBox(height: AppTheme.spacingXXXL),
              Text(
                widget.caption!,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(
                    duration: AppTheme.animSlow,
                    delay: const Duration(milliseconds: 900),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
