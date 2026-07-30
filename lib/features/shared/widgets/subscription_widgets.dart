import 'package:flutter/material.dart';

import '../../../core/subscription/subscription_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import 'avera_ui.dart';

Color subscriptionAccent(BuildContext context, SubscriptionAccentRole role) {
  final colors = Theme.of(context).colorScheme;
  return switch (role) {
    SubscriptionAccentRole.neutral => colors.outline,
    SubscriptionAccentRole.professional => colors.secondary,
    SubscriptionAccentRole.enterprise =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF2C45A)
          : const Color(0xFF8A5A00),
  };
}

Color subscriptionPlanAccent(BuildContext context, SubscriptionPlan plan) =>
    subscriptionAccent(
      context,
      SubscriptionPlanCatalogue.plan(plan).accentRole,
    );

class SubscriptionPlanSelector extends StatelessWidget {
  const SubscriptionPlanSelector({
    super.key,
    required this.selectedPlan,
    required this.onSelected,
  });

  final SubscriptionPlan selectedPlan;
  final ValueChanged<SubscriptionPlan> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final plan in SubscriptionPlan.values) ...[
        SubscriptionPlanCard(
          key: Key('subscription-plan-${plan.name}'),
          config: SubscriptionPlanCatalogue.plan(plan),
          selected: selectedPlan == plan,
          onTap: () => onSelected(plan),
        ),
        if (plan != SubscriptionPlan.values.last)
          const SizedBox(height: AveraSpacing.cardGap),
      ],
    ],
  );
}

class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.config,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionPlanConfig config;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = subscriptionAccent(context, config.accentRole);
    final surface = selected
        ? Color.alphaBlend(accent.withValues(alpha: .08), colors.surface)
        : colors.surface;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${config.name} plan${config.isRecommended ? ', recommended' : ''}. ${config.tagline}',
      child: Material(
        color: surface,
        elevation: selected ? 2 : 0,
        shadowColor: accent.withValues(alpha: .24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          side: BorderSide(
            color: selected ? accent : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AveraSpacing.largeCardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            config.name,
                            style: averaText(context).sectionTitle,
                          ),
                          if (config.isRecommended)
                            _RecommendedBadge(accent: accent),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PlanSelectionIndicator(selected: selected, accent: accent),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  config.tagline,
                  style: averaText(
                    context,
                  ).listItemTitle.copyWith(color: accent),
                ),
                const SizedBox(height: 8),
                Text(
                  'Best for: ${config.bestFor}',
                  style: averaText(context).listItemSubtitle,
                ),
                if (config.includesContext != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    config.includesContext!,
                    style: averaText(context).caption,
                  ),
                ],
                const SizedBox(height: 14),
                for (final benefit in config.highlightBenefits) ...[
                  _BenefitRow(text: benefit, accent: accent),
                  if (benefit != config.highlightBenefits.last)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'RECOMMENDED',
      style: averaText(context).caption.copyWith(
        color: Theme.of(context).colorScheme.onPrimary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _PlanSelectionIndicator extends StatelessWidget {
  const _PlanSelectionIndicator({required this.selected, required this.accent});
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('plan-selection-indicator'),
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? accent : Theme.of(context).colorScheme.outline,
        width: selected ? 2.5 : 1.5,
      ),
    ),
    alignment: Alignment.center,
    child: selected
        ? Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          )
        : null,
  );
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.check_rounded,
        key: const Key('plan-benefit-check'),
        size: 19,
        color: accent,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: averaText(context).listItemSubtitle)),
    ],
  );
}

class SubscriptionFeatureCell extends StatelessWidget {
  const SubscriptionFeatureCell({
    super.key,
    required this.value,
    required this.plan,
  });

  final SubscriptionFeatureValue value;
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: switch (value.type) {
        SubscriptionFeatureValueType.included => Icon(
          Icons.check_rounded,
          key: const Key('comparison-included-icon'),
          color: const Color(0xFF16856B),
          size: 21,
          semanticLabel: 'Included',
        ),
        SubscriptionFeatureValueType.unavailable => Text(
          '\u2014',
          key: const Key('comparison-unavailable'),
          style: averaText(context).listItemSubtitle,
          semanticsLabel: 'Unavailable',
        ),
        SubscriptionFeatureValueType.text => Text(
          value.text!,
          textAlign: TextAlign.center,
          style: averaText(context).caption.copyWith(
            color: subscriptionPlanAccent(context, plan),
            fontWeight: FontWeight.w700,
          ),
        ),
      },
    );
  }
}
