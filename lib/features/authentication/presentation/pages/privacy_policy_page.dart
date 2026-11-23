import 'package:flutter/material.dart';

import '../../../../core/constants/privacy_policy.dart' show PrivacyPolicyText;

import '../../../../shared/widgets/app_page.dart';
import '../../domain/entities/privacy_policy.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static Future<bool?> review(BuildContext context, {required int age}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _PrivacyPolicyAcceptance(age: age)),
      );

  @override
  Widget build(BuildContext context) => const AppPage(
    title: 'Privacy Policy',
    alignment: Alignment.topCenter,
    child: _PolicyText(),
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
  const _PolicyText();

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
        for (final (title, detail) in _sections) ...[
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(detail),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

const _sections = [
  (
    'Account and consent',
    'FitNEP uses your name and email to create your account. We ask for your '
        'age to determine whether you need permission from a parent or '
        'guardian. We save the age you enter, the date and version of your policy acceptance, '
        'and record your guardian consent confirmation if you are under 18.',
  ),
  ('Who can see your records', PrivacyPolicyText.recordAccess),
  (
    'Photos and device activity',
    'Meal photos, progress photos and device activity are optional. FitNEP '
        'does not collect them unless you enable the matching choice in '
        'Privacy preferences.',
  ),
  ('Changing your choices', PrivacyPolicyText.withdrawal),
];
