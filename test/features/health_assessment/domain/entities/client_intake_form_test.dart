import 'package:fitnep/features/authorization/data/profile_age.dart';
import 'package:fitnep/features/health_assessment/data/client_intake_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives age from date of birth at the guardian threshold', () {
    final today = DateTime.utc(2026, 11, 26);

    expect(ageFromBirthDate('2008-11-27', today), 17);
    expect(ageFromBirthDate('2008-11-26', today), 18);
    expect(ageFromBirthDate('2010-02-29', today), isNull);
    expect(ageFromBirthDate('2027-01-01', today), isNull);
  });

  test('calculates BMI to one decimal from valid height and weight', () {
    expect(intakeBmi('175', '70'), 22.9);
    expect(intakeBmi('175', ''), isNull);
    expect(intakeBmi('301', '70'), isNull);
    expect(intakeBmi('175', '0'), isNull);
    expect(IntakeField.waist.measurement('72.5'), 72.5);
    expect(IntakeField.waist.measurement('501'), isNull);
  });
}
