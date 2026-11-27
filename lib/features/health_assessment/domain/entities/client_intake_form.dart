import 'client_intake.dart';

enum IntakeField {
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

enum IntakeStep {
  measurements('Measurements and BMI', [
    IntakeField.height,
    IntakeField.weight,
    IntakeField.waist,
    IntakeField.hip,
    IntakeField.chest,
  ]),
  goalsAndHealth('Goals and health information', [
    IntakeField.goals,
    IntakeField.medicalHistory,
  ]),
  food('Food and dietary information', [
    IntakeField.allergies,
    IntakeField.restrictions,
    IntakeField.foodPreferences,
  ]);

  const IntakeStep(this.label, this.fields);

  final String label;
  final List<IntakeField> fields;
}

class IntakeFormWorkspace {
  const IntakeFormWorkspace({
    required this.answers,
    required this.version,
    required this.draftRevision,
    required this.profileReady,
    this.latest,
  });

  final Map<IntakeField, String> answers;
  final int version;
  final int draftRevision;
  final bool profileReady;
  final ClientIntake? latest;
}

typedef IntakeFormChange = ({
  Map<IntakeField, String> answers,
  int version,
  int draftRevision,
});

double? intakeBmi(String height, String weight) {
  final cm = IntakeField.height.measurement(height);
  final kg = IntakeField.weight.measurement(weight);
  if (cm == null || kg == null) return null;
  final metres = cm / 100;
  return (10 * (kg / (metres * metres))).round() / 10;
}

String? validateIntakeField(
  IntakeField field,
  String value, {
  required bool complete,
}) {
  if (value.isEmpty) {
    return complete && field.required ? '${field.label} is required.' : null;
  }
  if (field.range case (final min, final max)) {
    if (field.measurement(value) == null) {
      return 'Enter a value from $min to $max.';
    }
  }
  return null;
}
