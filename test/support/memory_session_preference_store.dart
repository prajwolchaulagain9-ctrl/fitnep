import 'package:fitnep/features/authentication/data/session_preference_store.dart';

class MemorySessionPreferenceStore implements SessionPreferenceStore {
  MemorySessionPreferenceStore({this.rememberSession});

  bool? rememberSession;
  int writes = 0;
  int clears = 0;

  @override
  Future<bool?> readRememberSession() async => rememberSession;

  @override
  Future<void> writeRememberSession(bool rememberSession) async {
    writes++;
    this.rememberSession = rememberSession;
  }

  @override
  Future<void> clearRememberSession() async {
    clears++;
    rememberSession = null;
  }
}
