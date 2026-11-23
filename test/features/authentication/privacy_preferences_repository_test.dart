import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/authentication/data/repositories/privacy_preferences_repository_impl.dart';
import 'package:fitnep/features/authentication/domain/entities/privacy_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and saves only the active client account preferences', () async {
    final auth = _Auth()..user = _User('first');
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    addTearDown(dio.close);
    final repository = PrivacyPreferencesRepositoryImpl(
      ApiClient(
        tokenStorage: TokenStorage(auth: auth, expectedUid: 'first'),
        dio: dio,
      ),
    );
    final requests = <RequestOptions>[];
    var enabled = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          expect(request.uri.path, '/privacy/preferences');
          expect(request.headers['Authorization'], 'Bearer token-first');
          if (request.method == 'PATCH') {
            expect(request.data, {'share_progress_photos': true});
            enabled = true;
          }
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: 200,
              data: {
                'data': {
                  'preferences': {
                    'share_nutrition_records': true,
                    'share_progress_photos': enabled,
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final initial = await repository.loadPreferences();
    expect(initial.shareNutritionRecords, isTrue);
    expect(initial.shareProgressPhotos, isFalse);
    expect(initial.shareActivityData, isFalse);
    final saved = await repository.setSharing(
      PrivacySharingCategory.progressPhotos,
      true,
    );
    expect(saved.shareNutritionRecords, isTrue);
    expect(saved.shareProgressPhotos, isTrue);
    expect(saved.shareMealPhotos, isFalse);
    expect((await repository.loadPreferences()).shareProgressPhotos, isTrue);

    auth.user = _User('second');
    await expectLater(
      repository.setSharing(PrivacySharingCategory.progressPhotos, false),
      throwsA(isA<DioException>()),
    );
    expect(requests.map((request) => request.method), ['GET', 'PATCH', 'GET']);
  });
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;

  @override
  User? get currentUser => user;
}

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'token-$uid';
}
