import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      foregroundColor: const Color(0xFF102637),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFDADCE0)),
      shape: const StadiumBorder(),
    ),
    icon: isLoading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Image.asset(
            AppAssets.googleLogo,
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
    label: Text(
      isLoading ? 'Connecting to Google\u2026' : 'Continue with Google',
    ),
  );
}

class AuthenticationDivider extends StatelessWidget {
  const AuthenticationDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('or', style: TextStyle(color: Color(0xFF657A8C))),
        ),
        Expanded(child: Divider()),
      ],
    ),
  );
}
