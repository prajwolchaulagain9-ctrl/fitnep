import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/fitnep_wordmark.dart';
import '../../../shared/widgets/wellness_illustration.dart';
import '../../../app/theme/theme_mode_controller.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _pages = PageController();
  int _page = 0;
  static const _slides = [
    (
      title: 'Small habits.\nA healthier you.',
      description: 'Eat well, move more and build a routine that fits your life. Your next chapter starts here.',
      icon: Icons.restaurant_rounded,
      detail: 'Nutrition made personal',
      detailIcon: Icons.spa_outlined,
    ),
    (
      title: 'Your goals.\nYour kind of plan.',
      description: 'Choose a package that suits you, with nutrition and fitness guidance to help you make steady progress.',
      icon: Icons.fitness_center_rounded,
      detail: 'One step at a time',
      detailIcon: Icons.check_circle_outline_rounded,
    ),
    (
      title: 'Better together.\nSupported every day.',
      description: 'Connect with your care team for check-ins, messages and encouragement along the way.',
      icon: Icons.diversity_1_rounded,
      detail: 'Your care team, close by',
      detailIcon: Icons.chat_bubble_outline_rounded,
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _showPage(int page) {
    _pages.animateToPage(
      page,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lastPage = _page == _slides.length - 1;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
                  child: Row(
                    children: [
                      const FitNepWordmark(width: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'FitNEP',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('welcome_skip_button'),
                        onPressed: () => context.pushNamed(AppRoutes.login),
                        child: const Text('Skip'),
                      ),
                      const ThemeModeButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    key: const Key('welcome_carousel'),
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final visualHeight = (constraints.maxHeight * 0.48)
                              .clamp(140.0, 270.0);
                          return SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: (constraints.maxHeight - 40).clamp(
                                  0.0,
                                  double.infinity,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ExcludeSemantics(
                                    child: _WelcomeVisual(
                                      scene: WellnessScene.values[index],
                                      height: visualHeight,
                                      icon: slide.icon,
                                      detail: slide.detail,
                                      detailIcon: slide.detailIcon,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    slide.title,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineLarge
                                        ?.copyWith(
                                          fontSize: 30,
                                          height: 1.18,
                                          letterSpacing: -0.8,
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    slide.description,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        label: 'Welcome page ${_page + 1} of ${_slides.length}',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _slides.length,
                            (index) => Semantics(
                              button: true,
                              selected: index == _page,
                              label: 'Page ${index + 1}',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => _showPage(index),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                      width: index == _page ? 24 : 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: index == _page
                                            ? colors.primary
                                            : colors.outlineVariant,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const Key('welcome_next_button'),
                        onPressed: () => lastPage
                            ? context.pushNamed(AppRoutes.signup)
                            : _showPage(_page + 1),
                        label: Text(lastPage ? 'Get started' : 'Next'),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                        iconAlignment: IconAlignment.end,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton(
                            key: const Key('welcome_login_button'),
                            onPressed: () => context.pushNamed(AppRoutes.login),
                            child: const Text('Log in'),
                          ),
                          TextButton(
                            onPressed: () => context.pushNamed(AppRoutes.about),
                            child: const Text('Learn about FitNEP'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeVisual extends StatelessWidget {
  const _WelcomeVisual({
    required this.height,
    required this.icon,
    required this.detail,
    required this.detailIcon,
    required this.scene,
  });
  final double height;
  final IconData icon;
  final String detail;
  final IconData detailIcon;
  final WellnessScene scene;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          WellnessIllustration(scene: scene, size: height * 0.84),
          Positioned(
            top: 12,
            right: 28,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colors.primary,
                size: 20,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(detailIcon, size: 22, color: colors.primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      detail,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
