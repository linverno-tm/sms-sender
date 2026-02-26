import 'package:flutter_test/flutter_test.dart';
import 'package:sms/services/phone_number_normalizer.dart';

void main() {
  final normalizer = PhoneNumberNormalizer();

  test('acceptance samples are normalized correctly', () {
    expect(normalizer.normalize('90 107 55 08'), '998901075508');
    expect(normalizer.normalize('+998 90 107 55 08'), '998901075508');
    expect(normalizer.normalize('998-90-107-55-08'), '998901075508');
    expect(normalizer.normalize('(90)1075508'), '998901075508');
    expect(normalizer.normalize('abc'), isNull);
    expect(normalizer.normalize('90107550'), isNull);
  });
}
