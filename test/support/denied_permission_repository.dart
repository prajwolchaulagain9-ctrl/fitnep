import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';
import 'package:fitnep/features/authorization/domain/account.dart';

class _Firestore extends Fake implements FirebaseFirestore {}

class DeniedPermissionRepository extends AuthorizationRepository {
  DeniedPermissionRepository()
    : super(Dio(BaseOptions(baseUrl: 'https://fitnep.test/')), _Firestore());
  @override
  Future<void> checkPermission(String permission) async {
    throw const AuthorizationFailure(
      'You do not have permission to access this feature.',
    );
  }
}
