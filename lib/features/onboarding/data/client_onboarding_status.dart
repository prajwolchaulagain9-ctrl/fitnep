import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authorization/data/account.dart';
import '../../authorization/data/authorization_repository.dart';

enum ClientOnboardingStatus { pending, skipped, completed }

class ClientOnboardingProgress {
  const ClientOnboardingProgress({
    required this.status,
    this.heightCm,
    this.weightKg,
  });

  factory ClientOnboardingProgress.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Missing onboarding progress.');
    }
    final status = switch (json['status']) {
      'required' || 'draft' => ClientOnboardingStatus.pending,
      'skipped' => ClientOnboardingStatus.skipped,
      'completed' => ClientOnboardingStatus.completed,
      _ => throw const FormatException('Unknown onboarding status.'),
    };
    return ClientOnboardingProgress(
      status: status,
      heightCm: json['heightCm'] as num?,
      weightKg: json['weightKg'] as num?,
    );
  }

  final ClientOnboardingStatus status;
  final num? heightCm;
  final num? weightKg;
}

final clientOnboardingProgressProvider = FutureProvider.autoDispose
    .family<ClientOnboardingProgress, String>((ref, uid) async {
      final response = await ref
          .watch(authorizationRepositoryProvider)
          .request('profile/me');
      if (response['account'] case {'id': final String id} when id == uid) {
        return ClientOnboardingProgress.fromJson(response['onboarding']);
      }
      throw const AuthorizationFailure(
        'Your session ended. Please sign in again.',
      );
    }, retry: (_, _) => null);

final clientOnboardingStatusProvider = FutureProvider.autoDispose
    .family<ClientOnboardingStatus, String>((ref, uid) async {
      final progress = await ref.watch(
        clientOnboardingProgressProvider(uid).future,
      );
      return progress.status;
    }, retry: (_, _) => null);
