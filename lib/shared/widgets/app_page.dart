import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.alignment = Alignment.center,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    required this.child,
  });

  final String? title;
  final Widget child;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          Theme.of(context).appBarTheme.systemOverlayStyle ??
          SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: title == null ? null : AppBar(title: Text(title!)),
        body: SafeArea(
          child: Align(
            alignment: alignment,
            child: SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
