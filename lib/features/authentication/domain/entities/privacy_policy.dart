const privacyPolicyVersion = '1';

typedef RegistrationConsent = ({int age, bool guardianConfirmed});

int? parseRegistrationAge(String? value) {
  final age = int.tryParse(value?.trim() ?? '', radix: 10);
  return age != null && age >= 1 && age <= 120 ? age : null;
}
