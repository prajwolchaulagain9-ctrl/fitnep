import 'package:flutter/material.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/legal_document.dart';
import '../../../shared/widgets/legal_links.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({this.anchor = '', super.key});
  final String anchor;

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Terms and Conditions',
    alignment: Alignment.topCenter,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Version 1'),
        const SizedBox(height: 16),
        LegalDocument(
          path: AppRoutes.termsPath,
          sections: _terms,
          anchor: anchor,
        ),
        const LegalLinks(),
      ],
    ),
  );
}

const _terms = <LegalSection>[
  (
    id: 'account',
    title: 'Your account',
    points: [
      'Provide accurate account information and keep your password private.',
      'Verify your email before accessing protected client features.',
      'Your account role and available features are assigned by FitNEP. Creating an account does not grant staff or administrator access.',
    ],
  ),
  (
    id: 'wellness',
    title: 'Health and wellness',
    points: [
      'FitNEP supports nutrition and fitness routines. It does not provide emergency medical care.',
      'Discuss medical conditions and changes to exercise or diet with a qualified healthcare professional.',
      'You can add height and weight during setup or return to them later. Profile and health intake hold additional information you choose to provide.',
    ],
  ),
  (
    id: 'packages',
    title: 'Packages and membership',
    points: [
      'Review the displayed price, duration and included features before confirming a package.',
      'Selecting a package saves a Pending membership. Selection alone does not confirm payment or activate membership.',
      'The FitNEP team verifies payment proof before activating a membership. A new package costs its full price and starts after any current paid term ends.',
    ],
  ),
  (
    id: 'conduct',
    title: 'Use of the app',
    points: [
      'Use only your own account and features authorized for your role.',
      'Do not attempt to access another user’s private records or interfere with the service.',
      'Accounts may be made inactive by the authorized FitNEP team. Contact that team if access is unavailable.',
    ],
  ),
  (
    id: 'privacy',
    title: 'Privacy and availability',
    points: [
      'Read the Privacy Policy for information about saved data and sharing choices.',
      'Some features are still being developed. Availability depends on the service and your account permissions.',
    ],
  ),
];
