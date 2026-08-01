import 'package:avera/core/router/activation_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verified HTTPS activation link passes its token to the activation route',
    () {
      const token = 'secure-production-activation-token';
      final uri = Uri.parse(
        'https://accounts.averavet.sbs/activate-clinic-admin?token=$token',
      );
      expect(clinicAdministratorActivationToken(uri), token);
    },
  );

  test(
    'custom-scheme fallback and internal GoRouter path remain supported',
    () {
      expect(
        clinicAdministratorActivationToken(
          Uri.parse('avera://app/activate-clinic-admin?token=fallback-token'),
        ),
        'fallback-token',
      );
      expect(
        clinicAdministratorActivationToken(
          Uri.parse('/activate-clinic-admin?token=router-token'),
        ),
        'router-token',
      );
    },
  );

  test('missing tokens and unverified hosts are rejected safely', () {
    expect(
      clinicAdministratorActivationToken(
        Uri.parse('https://accounts.averavet.sbs/activate-clinic-admin'),
      ),
      isNull,
    );
    expect(
      clinicAdministratorActivationToken(
        Uri.parse(
          'https://attacker.example/activate-clinic-admin?token=stolen',
        ),
      ),
      isNull,
    );
  });
}
