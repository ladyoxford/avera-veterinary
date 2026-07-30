enum SubscriptionPlan {
  starter('Starter'),
  professional('Professional'),
  enterprise('Enterprise');

  const SubscriptionPlan(this.label);

  final String label;

  static SubscriptionPlan fromStorage(String value) {
    return SubscriptionPlan.values.firstWhere(
      (plan) => plan.label.toLowerCase() == value.trim().toLowerCase(),
      orElse: () => SubscriptionPlan.starter,
    );
  }
}

enum SubscriptionAccentRole { neutral, professional, enterprise }

class SubscriptionPlanConfig {
  const SubscriptionPlanConfig({
    required this.tier,
    required this.tagline,
    required this.bestFor,
    required this.highlightBenefits,
    required this.accentRole,
    this.isRecommended = false,
    this.includesContext,
  });

  final SubscriptionPlan tier;
  final String tagline;
  final String bestFor;
  final bool isRecommended;
  final String? includesContext;
  final List<String> highlightBenefits;
  final SubscriptionAccentRole accentRole;

  String get name => tier.label;
}

enum SubscriptionFeatureValueType { included, unavailable, text }

class SubscriptionFeatureValue {
  const SubscriptionFeatureValue._(this.type, [this.text]);

  const SubscriptionFeatureValue.included()
    : this._(SubscriptionFeatureValueType.included);
  const SubscriptionFeatureValue.unavailable()
    : this._(SubscriptionFeatureValueType.unavailable);
  const SubscriptionFeatureValue.text(String value)
    : this._(SubscriptionFeatureValueType.text, value);

  final SubscriptionFeatureValueType type;
  final String? text;
}

class SubscriptionComparisonRow {
  const SubscriptionComparisonRow({
    required this.benefit,
    required this.values,
  });

  final String benefit;
  final Map<SubscriptionPlan, SubscriptionFeatureValue> values;
}

class SubscriptionPlanCatalogue {
  const SubscriptionPlanCatalogue._();

  static const plans = <SubscriptionPlan, SubscriptionPlanConfig>{
    SubscriptionPlan.starter: SubscriptionPlanConfig(
      tier: SubscriptionPlan.starter,
      tagline: 'Digital clinic management.',
      bestFor: 'New, small, or growing clinics',
      highlightBenefits: [
        'Digital medical files & records',
        'Appointments & hospitalization',
        'Inventory & billing tracking',
        'Basic Vera AI assistant',
      ],
      accentRole: SubscriptionAccentRole.neutral,
    ),
    SubscriptionPlan.professional: SubscriptionPlanConfig(
      tier: SubscriptionPlan.professional,
      tagline: 'Digital clinic management with an AI clinical assistant.',
      bestFor: 'Busy clinics automating clinical work',
      isRecommended: true,
      includesContext: 'Everything in Starter, plus:',
      highlightBenefits: [
        'AI clinical documentation & SOAP notes',
        'Drug dose & safety intelligence',
        'Advanced reports & analytics',
      ],
      accentRole: SubscriptionAccentRole.professional,
    ),
    SubscriptionPlan.enterprise: SubscriptionPlanConfig(
      tier: SubscriptionPlan.enterprise,
      tagline: 'AI-powered veterinary hospital operating system.',
      bestFor: 'Multi-branch hospitals and veterinary groups',
      includesContext: 'Everything in Professional, plus:',
      highlightBenefits: [
        'Multi-clinic command centre',
        'Predictive business intelligence',
        'API & custom integrations',
      ],
      accentRole: SubscriptionAccentRole.enterprise,
    ),
  };

  static SubscriptionPlanConfig plan(SubscriptionPlan tier) => plans[tier]!;

  static const comparisonRows = <SubscriptionComparisonRow>[
    SubscriptionComparisonRow(
      benefit: 'Digital medical records',
      values: _allIncluded,
    ),
    SubscriptionComparisonRow(
      benefit: 'Appointments and hospitalization',
      values: _allIncluded,
    ),
    SubscriptionComparisonRow(
      benefit: 'Inventory and billing',
      values: _allIncluded,
    ),
    SubscriptionComparisonRow(
      benefit: 'Staff roles and permissions',
      values: _allIncluded,
    ),
    SubscriptionComparisonRow(benefit: 'Basic Vera AI', values: _allIncluded),
    SubscriptionComparisonRow(
      benefit: 'AI clinical documentation',
      values: _professionalAndEnterprise,
    ),
    SubscriptionComparisonRow(
      benefit: 'AI differential and treatment assistance',
      values: _professionalAndEnterprise,
    ),
    SubscriptionComparisonRow(
      benefit: 'Drug safety and dose intelligence',
      values: _professionalAndEnterprise,
    ),
    SubscriptionComparisonRow(
      benefit: 'Workflow automation',
      values: {
        SubscriptionPlan.starter: SubscriptionFeatureValue.text('Basic'),
        SubscriptionPlan.professional: SubscriptionFeatureValue.text(
          'Advanced',
        ),
        SubscriptionPlan.enterprise: SubscriptionFeatureValue.text(
          'Enterprise',
        ),
      },
    ),
    SubscriptionComparisonRow(
      benefit: 'Advanced reports and analytics',
      values: _professionalAndEnterprise,
    ),
    SubscriptionComparisonRow(
      benefit: 'Multi-clinic command centre',
      values: _enterpriseOnly,
    ),
    SubscriptionComparisonRow(
      benefit: 'Predictive business intelligence',
      values: _enterpriseOnly,
    ),
    SubscriptionComparisonRow(
      benefit: 'External integrations and API access',
      values: {
        SubscriptionPlan.starter: SubscriptionFeatureValue.unavailable(),
        SubscriptionPlan.professional: SubscriptionFeatureValue.text('Limited'),
        SubscriptionPlan.enterprise: SubscriptionFeatureValue.text('Advanced'),
      },
    ),
    SubscriptionComparisonRow(
      benefit: 'Custom enterprise workflows',
      values: _enterpriseOnly,
    ),
    SubscriptionComparisonRow(
      benefit: 'Dedicated implementation support',
      values: _enterpriseOnly,
    ),
  ];

  static const _allIncluded = <SubscriptionPlan, SubscriptionFeatureValue>{
    SubscriptionPlan.starter: SubscriptionFeatureValue.included(),
    SubscriptionPlan.professional: SubscriptionFeatureValue.included(),
    SubscriptionPlan.enterprise: SubscriptionFeatureValue.included(),
  };

  static const _professionalAndEnterprise =
      <SubscriptionPlan, SubscriptionFeatureValue>{
        SubscriptionPlan.starter: SubscriptionFeatureValue.unavailable(),
        SubscriptionPlan.professional: SubscriptionFeatureValue.included(),
        SubscriptionPlan.enterprise: SubscriptionFeatureValue.included(),
      };

  static const _enterpriseOnly = <SubscriptionPlan, SubscriptionFeatureValue>{
    SubscriptionPlan.starter: SubscriptionFeatureValue.unavailable(),
    SubscriptionPlan.professional: SubscriptionFeatureValue.unavailable(),
    SubscriptionPlan.enterprise: SubscriptionFeatureValue.included(),
  };
}
