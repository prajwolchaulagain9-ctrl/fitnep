class ClientIntake {
  const ClientIntake({
    required this.clientId,
    required this.allergies,
    required this.medicalConditions,
    required this.sections,
    required this.submittedAt,
    required this.updatedAt,
  });

  final String clientId;
  final List<String> allergies;
  final List<String> medicalConditions;
  final List<ClientIntakeSection> sections;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
}

class ClientIntakeSection {
  const ClientIntakeSection({required this.title, required this.fields});

  final String title;
  final List<ClientIntakeField> fields;
}

class ClientIntakeField {
  const ClientIntakeField({required this.label, required this.value});

  final String label;
  final String value;
}
