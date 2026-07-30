import 'package:flutter/material.dart';

import '../../../core/branding/avera_brand_assets.dart';

enum AveraLogoVariant { full, compact, monochrome, splash }

class AveraLogo extends StatelessWidget {
  const AveraLogo({
    super.key,
    this.size = 72,
    this.variant = AveraLogoVariant.full,
    this.showWordmark = false,
    this.wordmarkColor,
    this.assetPathOverride,
  });

  final double size;
  final AveraLogoVariant variant;
  final bool showWordmark;
  final Color? wordmarkColor;
  @visibleForTesting
  final String? assetPathOverride;

  @override
  Widget build(BuildContext context) {
    final assetPath =
        assetPathOverride ??
        switch (variant) {
          AveraLogoVariant.full => AveraBrandAssets.primaryLogo,
          AveraLogoVariant.compact => AveraBrandAssets.compactLogo,
          AveraLogoVariant.monochrome => AveraBrandAssets.monochromeLogo,
          AveraLogoVariant.splash => AveraBrandAssets.splashLogo,
        };
    final mark = SizedBox.square(
      dimension: size,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        alignment: variant == AveraLogoVariant.splash
            ? Alignment.bottomCenter
            : Alignment.center,
        filterQuality: FilterQuality.high,
        semanticLabel: 'AVERA logo',
        errorBuilder: (_, __, ___) => _AveraLogoFallback(size: size),
      ),
    );

    if (!showWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * .12),
        Text(
          'AVERA',
          style: TextStyle(
            fontFamily: 'Sora',
            color: wordmarkColor ?? Theme.of(context).colorScheme.onSurface,
            fontSize: size * .2,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

class AveraCompactLogo extends StatelessWidget {
  const AveraCompactLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) =>
      AveraLogo(size: size, variant: AveraLogoVariant.compact);
}

class AveraBrandHeader extends StatelessWidget {
  const AveraBrandHeader({super.key, this.clinicName, this.logoSize = 44});

  final String? clinicName;
  final double logoSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AveraCompactLogo(size: logoSize),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AVERA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (clinicName case final name? when name.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _AveraLogoFallback extends StatelessWidget {
  const _AveraLogoFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(size * .18),
    ),
    child: Center(
      child: Text(
        'A',
        semanticsLabel: 'AVERA',
        style: TextStyle(
          fontFamily: 'Sora',
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: size * .56,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}
