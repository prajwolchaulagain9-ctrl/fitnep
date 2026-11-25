import 'package:flutter/material.dart';

import '../../../../core/constants/privacy_policy.dart' show PrivacyPolicyText;

import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/legal_document.dart';
import '../../../../app/routes/app_routes.dart';
import '../../domain/entities/privacy_policy.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({this.anchor = '', super.key});
  final String anchor;

  static Future<bool?> review(BuildContext context, {required int age}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _PrivacyPolicyAcceptance(age: age)),
      );

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Privacy Policy',
    alignment: Alignment.topCenter,
    child: _PolicyText(anchor: anchor),
  );
}

class _PrivacyPolicyAcceptance extends StatefulWidget {
  const _PrivacyPolicyAcceptance({required this.age});

  final int age;

  @override
  State<_PrivacyPolicyAcceptance> createState() =>
      _PrivacyPolicyAcceptanceState();
}

class _PrivacyPolicyAcceptanceState extends State<_PrivacyPolicyAcceptance> {
  final _scroll = ScrollController();
  bool _reachedEnd = false;
  bool _accepted = false;
  bool _guardian = false;

  bool get _requiresGuardian => widget.age < 18;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkScrollEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScrollEnd());
  }

  void _checkScrollEnd() {
    if (mounted &&
        !_reachedEnd &&
        _scroll.hasClients &&
        _scroll.position.hasContentDimensions &&
        _scroll.position.extentAfter <= 1) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 528),
                  child: ListView(
                    key: const Key('registration_policy_scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      const _PolicyText(),
                      if (_requiresGuardian)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'My parent or guardian has given permission',
                          ),
                          value: _guardian,
                          onChanged: _reachedEnd
                              ? (value) =>
                                    setState(() => _guardian = value == true)
                              : null,
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('I accept the FitNEP Privacy Policy'),
                        value: _accepted,
                        onChanged: _reachedEnd
                            ? (value) =>
                                  setState(() => _accepted = value == true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_reachedEnd)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Scroll to the end to accept the policy.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    FilledButton(
                      onPressed:
                          _reachedEnd &&
                              _accepted &&
                              (!_requiresGuardian || _guardian)
                          ? () => Navigator.pop(context, true)
                          : null,
                      child: const Text('Accept and continue'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyText extends StatelessWidget {
  const _PolicyText({this.anchor = ''});
  final String anchor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How FitNEP handles your data', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Version $privacyPolicyVersion'),
        const SizedBox(height: 24),
        LegalDocument(
          path: AppRoutes.privacyPolicyPath,
          sections: _sections,
          anchor: anchor,
        ),
      ],
    );
  }
}

const _sections = <LegalSection>[
  (
    id: 'account',
    title: 'Account and consent',
    points: [
      'FitNEP uses your name and email to create your account.',
      'We save the date and version of your policy and terms acceptance.',
      'Age and goals are collected during later onboarding. If you are under 18, parent or guardian permission must be confirmed during that process.',
    ],
  ),
  (
    id: 'records',
    title: 'Who can see your records',
    points: [PrivacyPolicyText.recordAccess],
  ),
  (
    id: 'photos',
    title: 'Photos and device activity',
    points: [
      'Meal photos, progress photos and device activity are optional.',
      'FitNEP does not collect them unless you enable the matching choice in Privacy preferences.',
    ],
  ),
  (
    id: 'choices',
    title: 'Changing your choices',
    points: [PrivacyPolicyText.withdrawal],
  ),
];
