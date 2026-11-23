import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/features/authentication/data/repositories/privacy_preferences_repository_impl.dart';
import 'package:fitnep/features/authentication/domain/entities/privacy_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'defaults to private and updates one sharing choice at a time',
    () async {
      final auth = _Auth()..user = _User('first');
      final document = _PreferencesDocument();
      final repository = PrivacyPreferencesRepositoryImpl(auth, document);

      expect(await repository.loadPreferences(), PrivacyPreferences.defaults);
      document.data['share_nutrition_records'] = true;
      final saved = await repository.setSharing(
        PrivacySharingCategory.progressPhotos,
        true,
      );
      expect(saved.shareNutritionRecords, isTrue);
      expect(saved.shareProgressPhotos, isTrue);
      expect(saved.shareMealPhotos, isFalse);
      expect((await repository.loadPreferences()).shareProgressPhotos, isTrue);

      document.firestore.online = false;
      await expectLater(
        repository.setSharing(PrivacySharingCategory.progressPhotos, false),
        throwsStateError,
      );
      expect(document.data['share_progress_photos'], isTrue);

      document.firestore.online = true;
      auth.user = _User('second');
      await expectLater(
        repository.setSharing(PrivacySharingCategory.progressPhotos, false),
        throwsStateError,
      );
      expect(document.writes, hasLength(1));
    },
  );
}

// ignore: subtype_of_sealed_class
class _PreferencesDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  @override
  String get id => 'first';

  final data = <String, dynamic>{};
  final writes = <Map<String, dynamic>>[];
  @override
  late final _PreferencesFirestore firestore = _PreferencesFirestore(this);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    return _PreferencesSnapshot(data.isEmpty ? null : Map.of(data));
  }
}

class _PreferencesFirestore extends Fake implements FirebaseFirestore {
  _PreferencesFirestore(this.document);
  final _PreferencesDocument document;
  bool online = true;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (!online) throw StateError('Firestore is offline.');
    return transactionHandler(_PreferencesTransaction(document));
  }
}

class _PreferencesTransaction extends Fake implements Transaction {
  _PreferencesTransaction(this.document);
  final _PreferencesDocument document;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    expect(reference, same(document));
    return _PreferencesSnapshot(Map.of(document.data)) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    expect(reference, same(document));
    final changes = data as Map<String, dynamic>;
    expect(options?.merge, isTrue);
    expect(changes, {
      'share_progress_photos': true,
      'updated_at': isA<FieldValue>(),
    });
    document.writes.add(changes);
    document.data.addAll(changes);
    return this;
  }
}

// ignore: subtype_of_sealed_class
class _PreferencesSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _PreferencesSnapshot(this._data);
  final Map<String, dynamic>? _data;

  @override
  Map<String, dynamic>? data() => _data;
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
}
