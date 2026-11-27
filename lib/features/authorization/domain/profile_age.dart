int? ageFromBirthDate(String text, DateTime today) {
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
