import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/location/country_catalog.dart';

void main() {
  test('country catalogue contains the complete unique ISO set', () {
    expect(CountryCatalog.all.length, 249);
    expect(
      CountryCatalog.all.map((country) => country.isoAlpha2).toSet().length,
      CountryCatalog.all.length,
    );
    expect(CountryCatalog.byAlpha2('NG')?.displayName, 'Nigeria');
    expect(CountryCatalog.byAlpha2('GB')?.displayName, 'United Kingdom');
    expect(CountryCatalog.byAlpha2('US')?.displayName, 'United States');
    expect(CountryCatalog.byAlpha2('AE')?.displayName, 'United Arab Emirates');
    expect(CountryCatalog.byAlpha2('ZW')?.displayName, 'Zimbabwe');
  });

  test('country search supports names and alpha codes', () {
    expect(
      CountryCatalog.search(' nige ').map((country) => country.isoAlpha2),
      contains('NG'),
    );
    expect(
      CountryCatalog.search('gb').map((country) => country.displayName),
      contains('United Kingdom'),
    );
    expect(
      CountryCatalog.search('USA').map((country) => country.displayName),
      contains('United States'),
    );
    expect(CountryCatalog.search('').length, 249);
  });
}
