import 'client_intake.dart';

enum IntakeField {
  fullName('full_name', 'Full name', 160, required: true),
  age('age', 'Age', 3, required: true),
  dateOfBirth('date_of_birth', 'Date of birth', 10, required: true),
  email('contact_email', 'Contact email', 254),
  phone('contact_phone', 'Contact phone', 32),
  height('height_cm', 'Height (cm)', 16, required: true, range: (30, 300)),
  weight('weight_kg', 'Weight (kg)', 16, required: true, range: (1, 500)),
  waist('waist_cm', 'Waist (cm)', 16, range: (1, 500)),
  hip('hip_cm', 'Hips (cm)', 16, range: (1, 500)),
  chest('chest_cm', 'Chest (cm)', 16, range: (1, 500)),
  goals('fitness_goals', 'Fitness goals', 1000, required: true),
  medicalHistory('medical_history', 'Medical history', 1000, required: true),
  allergies('allergies', 'Food allergies', 1000, required: true),
  restrictions(
    'dietary_restrictions',
    'Dietary restrictions',
    1000,
    required: true,
  ),
  foodPreferences('food_preferences', 'Food preferences', 1000, required: true);

  const IntakeField(
    this.key,
    this.label,
    this.maxLength, {
    this.required = false,
    this.range,
  });

  final String key;
  final String label;
  final int maxLength;
  final bool required;
  final (int, int)? range;

  double? measurement(String value) {
    if (range case (final min, final max)) {
      if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) return null;
      final number = double.tryParse(value);
      if (number != null && number >= min && number <= max) return number;
    }
    return null;
  }
}

class IntakeFormWorkspace {
  const IntakeFormWorkspace({
    required this.answers,
    required this.version,
    required this.draftRevision,
    required this.membershipActive,
    required this.guardianConfirmed,
    this.latest,
  });

  final Map<IntakeField, String> answers;
  final int version;
  final int draftRevision;
  final bool membershipActive;
  final bool guardianConfirmed;
  final ClientIntake? latest;
}

typedef IntakeFormChange = ({
  Map<IntakeField, String> answers,
  int version,
  int draftRevision,
  bool guardianConfirmed,
});

int? validIntakeAge(String text) {
  if (!RegExp(r'^\d{1,3}$').hasMatch(text)) return null;
  final age = int.tryParse(text);
  return age != null && age >= 1 && age <= 120 ? age : null;
}

int? intakeBirthAge(String text, DateTime today) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final birthday = DateTime.tryParse('${text}T00:00:00Z');
  if (birthday == null || birthday.toIso8601String().substring(0, 10) != text) {
    return null;
  }
  final date = today.toUtc();
  var years = date.year - birthday.year;
  if (date.month < birthday.month ||
      (date.month == birthday.month && date.day < birthday.day)) {
    years--;
  }
  return years >= 1 && years <= 120 ? years : null;
}

double? intakeBmi(String height, String weight) {
  final cm = IntakeField.height.measurement(height);
  final kg = IntakeField.weight.measurement(weight);
  if (cm == null || kg == null) return null;
  final metres = cm / 100;
  return (10 * (kg / (metres * metres))).round() / 10;
}

bool needsIntakeGuardian(Map<IntakeField, String> answers, DateTime today) {
  final age = validIntakeAge(answers[IntakeField.age] ?? '');
  final birthAge = intakeBirthAge(
    answers[IntakeField.dateOfBirth] ?? '',
    today,
  );
  return (age != null && age < 18) || (birthAge != null && birthAge < 18);
}

String? validateIntakeField(
  IntakeField field,
  Map<IntakeField, String> answers, {
  required DateTime today,
  required bool complete,
}) {
  final value = answers[field] ?? '';
  if (value.isEmpty) {
    if (complete && field.required) return '${field.label} is required.';
    if (complete &&
        field == IntakeField.email &&
        (answers[IntakeField.phone]?.isEmpty ?? true)) {
      return 'Enter a contact email or phone number.';
    }
    return null;
  }
  if (field.range case (final min, final max)) {
    return field.measurement(value) == null
        ? 'Enter a value from $min to $max.'
        : null;
  }
  if (field == IntakeField.age) {
    final age = validIntakeAge(value);
    if (age == null) return 'Enter a whole age from 1 to 120.';
    final fromBirth = intakeBirthAge(
      answers[IntakeField.dateOfBirth] ?? '',
      today,
    );
    if (complete && fromBirth != null && age != fromBirth) {
      return 'Age must match your date of birth.';
    }
  }
  if (field == IntakeField.dateOfBirth &&
      intakeBirthAge(value, today) == null) {
    return 'Enter a valid date in YYYY-MM-DD format.';
  }
  if (complete &&
      field == IntakeField.email &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
    return 'Enter a valid email address.';
  }
  if (complete &&
      field == IntakeField.phone &&
      (!RegExp(r'^\+?[0-9 ().-]+$').hasMatch(value) ||
          !RegExp(r'^\d{7,15}$')
              .hasMatch(value.replaceAll(RegExp(r'\D'), '')))) {
    return 'Enter a phone number with 7 to 15 digits.';
  }
  return null;
}
