import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/meeting_model.dart';
import 'data/meeting_repository.dart';
import 'data/settings_repository.dart';
import 'services/recording_controller.dart';
import 'services/upload_service.dart';

final meetingRepositoryProvider = Provider<MeetingRepository>((ref) {
  throw UnimplementedError('override in main');
});

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository());

final dioProvider = Provider<Dio>(
  (ref) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 30),
      ),
    );

    // Диагностика: чтобы видеть в консоли, на каком запросе ломается выгрузка.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          debugPrint('[HTTP] → ${o.method} ${o.uri}');
          h.next(o);
        },
        onResponse: (r, h) {
          debugPrint('[HTTP] ← ${r.statusCode} ${r.requestOptions.uri}');
          h.next(r);
        },
        onError: (e, h) {
          final data = e.response?.data;
          if (data != null) {
            debugPrint('[HTTP] body: $data');
          }
          debugPrint(
            '[HTTP] ✕ ${e.type} ${e.response?.statusCode ?? '-'} '
            '${e.requestOptions.method} ${e.requestOptions.uri} '
            '${e.message}',
          );
          h.next(e);
        },
      ),
    );

    return dio;
  },
);

final uploadServiceProvider = Provider<UploadService>(
  (ref) => UploadService(
    ref.watch(dioProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>(
  (ref) => RecordingController(ref.watch(meetingRepositoryProvider)),
);

final meetingsListProvider =
    FutureProvider.autoDispose<List<Meeting>>((ref) async {
  final repo = ref.watch(meetingRepositoryProvider);
  return repo.listMeetings();
});
