import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

final backendResolverProvider = Provider<BackendResolver>((ref) {
  final resolver = BackendResolver(candidates: AppConfig.apiCandidates);
  ref.onDispose(resolver.close);
  return resolver;
});

class BackendResolver {
  BackendResolver({
    required this.candidates,
    this.probe,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final List<String> candidates;
  final Future<bool> Function(String)? probe;
  final DateTime Function() _now;
  final _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 1200),
      receiveTimeout: const Duration(milliseconds: 1200),
    ),
  );
  final _unavailableUntil = <String, DateTime>{};
  String? _selected;
  DateTime? _selectedAt;
  Future<String>? _selecting;

  Future<String> resolve() {
    if (candidates.isEmpty) return Future.value('');
    if (_selected != null &&
        _selectedAt != null &&
        _now().difference(_selectedAt!) < const Duration(seconds: 15) &&
        !_blocked(_selected!)) {
      return Future.value(_selected);
    }
    return _selecting ??= _resolve().whenComplete(() => _selecting = null);
  }

  Future<String> _resolve() async {
    var selected = candidates.last;
    // The final remote URL is tried by the actual request, allowing Render to
    // wake using the existing session-service timeout rather than a short probe.
    for (final candidate in candidates.take(candidates.length - 1)) {
      if (!_blocked(candidate) && await _healthy(candidate)) {
        selected = candidate;
        break;
      }
    }
    _selected = selected;
    _selectedAt = _now();
    return selected;
  }

  Future<bool> _healthy(String baseUrl) async {
    final check = probe;
    if (check != null) return check(baseUrl);
    try {
      final response = await _http.get<Object?>('${baseUrl}healthz');
      return response.data is Map &&
          (response.data as Map)['data'] is Map &&
          ((response.data as Map)['data'] as Map)['ready'] == true;
    } on DioException {
      return false;
    }
  }

  bool _blocked(String baseUrl) =>
      _unavailableUntil[baseUrl]?.isAfter(_now()) == true;

  void unavailable(String baseUrl) {
    _unavailableUntil[baseUrl] = _now().add(const Duration(seconds: 15));
    _selected = null;
    _selectedAt = null;
  }

  void close() => _http.close(force: true);
}

bool isBackendConnectionFailure(DioException error) =>
    error.response == null &&
    const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    }.contains(error.type);
