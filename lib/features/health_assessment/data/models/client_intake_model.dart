import '../../domain/entities/client_intake.dart';

class ClientIntakeModel extends ClientIntake {
  const ClientIntakeModel({
    required super.clientId,
    required super.allergies,
    required super.medicalConditions,
    required super.sections,
    required super.submittedAt,
    required super.updatedAt,
  });

  factory ClientIntakeModel.fromJson(
    Map<String, dynamic> json, {
    required String requestedClientId,
  }) {
    final clientId = _requiredString(json['client_id']);
    if (clientId != requestedClientId) {
      throw const FormatException('The intake belongs to another client.');
    }
    return ClientIntakeModel(
      clientId: clientId,
      allergies: _stringList(json['allergies']),
      medicalConditions: _stringList(json['medical_conditions']),
      sections: _sections(json['sections']),
      submittedAt: _date(json['submitted_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  static List<ClientIntakeSection> _sections(Object? value) {
    if (value is! List) throw const FormatException('Invalid intake sections.');
    return List<ClientIntakeSection>.unmodifiable(
      value.map((section) {
        if (section is! Map) {
          throw const FormatException('Invalid intake section.');
        }
        final json = Map<String, dynamic>.from(section);
        final fields = json['fields'];
        if (fields is! List) {
          throw const FormatException('Invalid intake fields.');
        }
        return ClientIntakeSection(
          title: _requiredString(json['title']),
          fields: List<ClientIntakeField>.unmodifiable(
            fields.map((field) {
              if (field is! Map) {
                throw const FormatException('Invalid intake field.');
              }
              final data = Map<String, dynamic>.from(field);
              return ClientIntakeField(
                label: _requiredString(data['label']),
                value: _requiredString(data['value']),
              );
            }),
          ),
        );
      }),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) throw const FormatException('Invalid intake list.');
    return List<String>.unmodifiable(value.map(_requiredString));
  }

  static String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Missing intake text.');
    }
    return value.trim();
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid intake date.');
    return DateTime.tryParse(value)?.toLocal() ??
        (throw const FormatException('Invalid intake date.'));
  }
}
