import 'package:dio/dio.dart';
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
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
    ),
  ),
);

final uploadServiceProvider = Provider<UploadService>(
  (ref) => UploadService(ref.watch(dioProvider)),
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
