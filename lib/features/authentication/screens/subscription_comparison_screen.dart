import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/clinic_registration_provider.dart';
import '../../../core/subscription/subscription_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/subscription_widgets.dart';

class ClinicSubscriptionComparisonScreen extends ConsumerStatefulWidget {
  const ClinicSubscriptionComparisonScreen({super.key});

  static const _tableWidth = 900.0;
  static const _benefitWidth = 330.0;
  static const _planWidth = 190.0;

  @override
  ConsumerState<ClinicSubscriptionComparisonScreen> createState() =>
      _ClinicSubscriptionComparisonScreenState();
}

class _ClinicSubscriptionComparisonScreenState
    extends ConsumerState<ClinicSubscriptionComparisonScreen> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = ref.watch(clinicRegistrationPlanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recommended Comparison')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            36,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AveraPageHeader(
                title: 'Recommended Comparison',
                subtitle: 'See exactly what each plan unlocks',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const Key('subscription-comparison-horizontal-scroll'),
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: ClinicSubscriptionComparisonScreen._tableWidth,
                    child: _ComparisonTable(selectedPlan: selectedPlan),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('Choose a plan', style: averaText(context).sectionTitle),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final plan in SubscriptionPlan.values)
                    plan == selectedPlan
                        ? FilledButton.icon(
                            key: Key('compare-select-${plan.name}'),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.check_rounded),
                            label: Text('${plan.label} selected'),
                          )
                        : OutlinedButton(
                            key: Key('compare-select-${plan.name}'),
                            onPressed: () {
                              ref
                                      .read(
                                        clinicRegistrationPlanProvider.notifier,
                                      )
                                      .state =
                                  plan;
                              Navigator.pop(context);
                            },
                            child: Text('Select ${plan.label}'),
                          ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.selectedPlan});
  final SubscriptionPlan selectedPlan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          children: [
            _tableRow(
              context,
              background: colors.surfaceContainerHighest,
              children: [
                _header(context, 'Benefit', null),
                for (final plan in SubscriptionPlan.values)
                  _header(context, plan.label, plan),
              ],
            ),
            for (
              var index = 0;
              index < SubscriptionPlanCatalogue.comparisonRows.length;
              index++
            )
              _comparisonRow(
                context,
                SubscriptionPlanCatalogue.comparisonRows[index],
                index,
              ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonRow(
    BuildContext context,
    SubscriptionComparisonRow row,
    int index,
  ) {
    final colors = Theme.of(context).colorScheme;
    return _tableRow(
      context,
      background: index.isEven ? colors.surface : colors.surfaceContainerLowest,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(row.benefit, style: averaText(context).listItemSubtitle),
        ),
        for (final plan in SubscriptionPlan.values)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SubscriptionFeatureCell(
              value: row.values[plan]!,
              plan: plan,
            ),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, String label, SubscriptionPlan? plan) =>
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: plan == null
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (plan == selectedPlan) ...[
              Icon(
                Icons.radio_button_checked_rounded,
                size: 16,
                color: subscriptionPlanAccent(context, plan!),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: plan == null ? TextAlign.start : TextAlign.center,
                style: averaText(context).listItemTitle.copyWith(
                  color: plan == null
                      ? null
                      : subscriptionPlanAccent(context, plan),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tableRow(
    BuildContext context, {
    required Color background,
    required List<Widget> children,
  }) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: ClinicSubscriptionComparisonScreen._benefitWidth,
              child: children.first,
            ),
            for (var index = 1; index < children.length; index++) ...[
              VerticalDivider(width: 1, thickness: 1, color: divider),
              SizedBox(
                width: ClinicSubscriptionComparisonScreen._planWidth - 1,
                child: children[index],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
