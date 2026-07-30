import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../subscription/subscription_plan_config.dart';

final clinicRegistrationPlanProvider =
    StateProvider.autoDispose<SubscriptionPlan>(
      (ref) => SubscriptionPlan.starter,
    );
