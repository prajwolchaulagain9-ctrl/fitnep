import 'package:fitnep/features/health_assessment/domain/entities/client_intake_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates stated age and date of birth at the guardian threshold', () {
    final today = DateTime.utc(2026, 11, 26);

    expect(validIntakeAge('17'), 17);
    expect(validIntakeAge('18'), 18);
    expect(validIntakeAge('0'), isNull);
    expect(validIntakeAge('17.5'), isNull);
    expect(intakeBirthAge('2008-11-27', today), 17);
    expect(intakeBirthAge('2008-11-26', today), 18);
    expect(intakeBirthAge('2010-02-29', today), isNull);
    expect(intakeBirthAge('2027-01-01', today), isNull);
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
