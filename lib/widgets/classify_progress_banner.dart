import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Elegant progress indicator shown while tracks are being classified in
/// the background — a slow breathing glow + note icon and an animated
/// progress bar, instead of a plain spinner.
class ClassifyProgressBanner extends StatefulWidget {
  final int progress;
  final int total;

  const ClassifyProgressBanner({
    super.key,
    required this.progress,
    required this.total,
  });

  @override
  State<ClassifyProgressBanner> createState() => _ClassifyProgressBannerState();
}

class _ClassifyProgressBannerState extends State<ClassifyProgressBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.total == 0 ? 0.0 : widget.progress / widget.total;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingS,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: AppTheme.accentPrimary.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final glow = 0.3 + (_controller.value * 0.5);
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accentPrimary.withOpacity(0.12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentPrimary.withOpacity(glow * 0.5),
                        blurRadius: 12 + (_controller.value * 10),
                        spreadRadius: 1 + (_controller.value * 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: AppTheme.accentPrimary.withOpacity(0.7 + glow * 0.3),
                    size: 20,
                  ),
                );
              },
            ),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Classification en cours…',
                    style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: AppTheme.backgroundCardElevated,
                        valueColor: AlwaysStoppedAnimation(AppTheme.accentPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.progress} / ${widget.total} morceaux',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
