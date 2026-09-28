import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

/// Shimmer skeleton loader for loading states
class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppTheme.radiusM,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.backgroundCard,
      highlightColor: AppTheme.backgroundCardElevated,
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }

  /// Skeleton for a track list item
  static Widget trackTile() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingS,
      ),
      child: Row(
        children: [
          SkeletonLoader(
            width: 56,
            height: 56,
            borderRadius: AppTheme.radiusM,
          ),
          SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: double.infinity,
                  height: 14,
                  borderRadius: AppTheme.radiusS,
                ),
                SizedBox(height: AppTheme.spacingS),
                SkeletonLoader(
                  width: 120,
                  height: 12,
                  borderRadius: AppTheme.radiusS,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Skeleton for a mood card
  static Widget moodCard() {
    return const SkeletonLoader(
      width: 160,
      height: 120,
      borderRadius: AppTheme.radiusL,
    );
  }

  /// Skeleton for cover art (player)
  static Widget coverArt({double size = 280}) {
    return SkeletonLoader(
      width: size,
      height: size,
      borderRadius: AppTheme.radiusXL,
    );
  }

  /// Skeleton for the mini player
  static Widget miniPlayer() {
    return Container(
      height: 64,
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingS,
      ),
      child: Shimmer.fromColors(
        baseColor: AppTheme.backgroundCard,
        highlightColor: AppTheme.backgroundCardElevated,
        child: const Row(
          children: [
            SkeletonLoader(
              width: 48,
              height: 48,
              borderRadius: AppTheme.radiusS,
            ),
            SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(
                    width: double.infinity,
                    height: 14,
                    borderRadius: AppTheme.radiusS,
                  ),
                  SizedBox(height: AppTheme.spacingXS),
                  SkeletonLoader(
                    width: 100,
                    height: 12,
                    borderRadius: AppTheme.radiusS,
                  ),
                ],
              ),
            ),
            SkeletonLoader(
              width: 40,
              height: 40,
              borderRadius: AppTheme.radiusFull,
            ),
          ],
        ),
      ),
    );
  }
}
