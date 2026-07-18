import 'package:flutter_test/flutter_test.dart';
import 'package:zevora/core/services/feature_gate_service.dart';

void main() {
  test(
    'Starter includes essential clinic operations but not advanced modules',
    () {
      expect(
        FeatureGateService.canAccess(
          subscriptionPlan: 'Starter',
          feature: AveraFeature.patientRecords,
        ),
        isTrue,
      );
      expect(
        FeatureGateService.canAccess(
          subscriptionPlan: 'Starter',
          feature: AveraFeature.hospitalization,
        ),
        isFalse,
      );
    },
  );

  test(
    'Professional unlocks clinical intelligence but not corporate analytics',
    () {
      expect(
        FeatureGateService.canAccess(
          subscriptionPlan: 'Professional',
          feature: AveraFeature.laboratory,
        ),
        isTrue,
      );
      expect(
        FeatureGateService.canAccess(
          subscriptionPlan: 'Professional',
          feature: AveraFeature.corporateAnalytics,
        ),
        isFalse,
      );
    },
  );

  test('Enterprise grants every implemented capability', () {
    for (final feature in AveraFeature.values) {
      expect(
        FeatureGateService.canAccess(
          subscriptionPlan: 'Enterprise',
          feature: feature,
        ),
        isTrue,
      );
    }
  });

  test('repository callers receive an explicit entitlement error', () {
    expect(
      () => FeatureGateService.requireAccess(
        subscriptionPlan: 'Starter',
        feature: AveraFeature.surgery,
      ),
      throwsA(isA<FeatureAccessDenied>()),
    );
  });
}
