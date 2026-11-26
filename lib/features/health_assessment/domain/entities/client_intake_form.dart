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
