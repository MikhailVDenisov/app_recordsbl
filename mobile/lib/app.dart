import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/meeting_model.dart';
import 'providers.dart';
import 'services/retry_policy.dart';
import 'services/upload_service.dart';
import 'ui/home_screen.dart';

class RecordsApp extends ConsumerStatefulWidget {
  const RecordsApp({super.key});

  @override
  ConsumerState<RecordsApp> createState() => _RecordsAppState();
}

class _RecordsAppState extends ConsumerState<RecordsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryFailedUploads();
    }
  }

  Future<void> _retryFailedUploads() async {
    final repo = ref.read(meetingRepositoryProvider);
    final upload = ref.read(uploadServiceProvider);
    final now = DateTime.now();
    final list = await repo.listMeetings();
    for (final m in list) {
      if (m.uploadStatus != LocalUploadStatus.error) continue;
      if (m.nextRetryAt != null && m.nextRetryAt!.isAfter(now)) continue;
      try {
        await upload.uploadMeeting(meeting: m, repo: repo);
        ref.invalidate(meetingsListProvider);
      } catch (e) {
        await repo.upsert(markUploadError(m, e, m.retryAttempt));
        ref.invalidate(meetingsListProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'АИСТ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
