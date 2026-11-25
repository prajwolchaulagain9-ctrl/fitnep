const privacyPolicyVersion = '2';

abstract final class PrivacyPolicyText {
  static const recordAccess =
      'You can view your saved records. Your current assigned FitNEP team '
      'includes your dietitian and any explicitly assigned support staff or '
      'admin. They can view only the categories you choose to share. '
      'Other clients and unassigned team members cannot view your private records.';
  static const sharingIntroduction =
      'Choose what your assigned FitNEP team can view. Each choice is off '
      'until you turn it on.';
  static const sharedVisibility =
      'Visible to you and your assigned FitNEP team.';
  static const privateVisibility = 'Visible only to you.';
  static const withdrawal =
      'Turning off photo or activity sharing stops new collection and removes '
      'your assigned team’s access. Your saved records remain available to you. '
      'Turning off nutrition sharing keeps your manually entered logs private.';
}
