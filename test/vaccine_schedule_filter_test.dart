import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/models/vaccine_catalogue.dart';

void main() {
  final now = DateTime(2026, 7, 23, 11);

  test('due-now predicate is shared by dashboard and schedule filtering', () {
    expect(
      isVaccinationActionRequired('Completed', DateTime(2026, 7, 23, 18), now),
      isTrue,
    );
    expect(
      isVaccinationActionRequired('Completed', DateTime(2026, 7, 24), now),
      isFalse,
    );
    expect(
      isVaccinationActionRequired('Cancelled', DateTime(2026, 7, 20), now),
      isFalse,
    );
    expect(isVaccinationActionRequired('Deferred', null, now), isFalse);
  });
}
