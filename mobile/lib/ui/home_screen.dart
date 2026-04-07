import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../core/format_duration.dart';
import '../data/meeting_model.dart';
import '../providers.dart';
import '../services/disk_space_service.dart';
import '../services/recording_controller.dart';
import '../services/retry_policy.dart';
import '../services/upload_service.dart';
import 'app_branding.dart';
import 'meeting_playback_sheet.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _uploadProgress = <String, UploadProgress>{};

  Future<void> _playMeeting(Meeting m) async {
    final file = File(m.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл записи не найден')),
      );
      return;
    }
    await openMeetingPlayback(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(recordingControllerProvider);
    final meetings = ref.watch(meetingsListProvider);
    final repo = ref.watch(meetingRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AistAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              ref.invalidate(meetingsListProvider);
            },
          ),
        ],
      ),
      body: meetings.when(
        data: (list) {
          final incomplete = list.where((m) => m.incomplete).toList();
          final canStart = rec.phase == RecordingPhase.idle &&
              incomplete.isEmpty &&
              !rec.blockedByDisk;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: canStart
                      ? () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const RecordingScreen(),
                            ),
                          );
                          ref.invalidate(meetingsListProvider);
                        }
                      : null,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Начать запись встречи'),
                ),
              ),
              if (incomplete.isNotEmpty)
                MaterialBanner(
                  content: const Text(
                    'Есть незавершённая встреча. Завершите или удалите её.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        for (final m in incomplete) {
                          await repo.delete(m.id);
                        }
                        ref.invalidate(meetingsListProvider);
                      },
                      child: const Text('Сбросить'),
                    ),
                  ],
                ),
              if (rec.warning != null)
                ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(_diskText(rec.warning!)),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Ранее записанные встречи',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final m = list[i];
                    return _MeetingTile(
                      meeting: m,
                      progress: _uploadProgress[m.id],
                      onPlay: () => _playMeeting(m),
                      onUpload: () => _upload(context, m),
                      onDelete: () async {
                        await repo.delete(m.id);
                        ref.invalidate(meetingsListProvider);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }

  String _diskText(DiskWarning w) {
    switch (w) {
      case DiskWarning.warn:
        return 'Мало места на диске (< 100 МБ).';
      case DiskWarning.critical:
        return 'Критически мало места (< 10 МБ).';
      default:
        return '';
    }
  }

  Future<void> _upload(BuildContext context, Meeting m) async {
    if (m.uploadStatus == LocalUploadStatus.uploaded) return;

    final repo = ref.read(meetingRepositoryProvider);
    final upload = ref.read(uploadServiceProvider);
    final file = File(m.filePath);
    int totalBytes = m.fileSizeBytes;
    if (await file.exists()) {
      totalBytes = await file.length();
    }
    setState(() {
      _uploadProgress[m.id] = UploadProgress(
        sentBytes: m.uploadedBytes.clamp(0, totalBytes),
        totalBytes: totalBytes > 0 ? totalBytes : 1,
        etaSeconds: null,
      );
    });
    try {
      await repo.upsert(
        m.copyWith(uploadStatus: LocalUploadStatus.uploading),
      );
      await upload.uploadMeeting(
        meeting: m.copyWith(uploadStatus: LocalUploadStatus.uploading),
        repo: repo,
        onProgress: (p) {
          setState(() => _uploadProgress[m.id] = p);
        },
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выгрузка завершена')),
        );
      }
    } catch (e) {
      final updated = markUploadError(m, e, m.retryAttempt);
      await repo.upsert(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выгрузки: $e')),
        );
      }
    } finally {
      setState(() => _uploadProgress.remove(m.id));
      ref.invalidate(meetingsListProvider);
    }
  }
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({
    required this.meeting,
    required this.onPlay,
    required this.onUpload,
    required this.onDelete,
    this.progress,
  });

  final Meeting meeting;
  final UploadProgress? progress;
  final VoidCallback onPlay;
  final VoidCallback onUpload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yy HH:mm');
    final status = _statusLabel(meeting.uploadStatus);

    Future<void> confirmDelete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Удалить встречу?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (ok == true) onDelete();
    }

    return Slidable(
      key: ValueKey(meeting.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.16,
        children: [
          CustomSlidableAction(
            onPressed: (_) => confirmDelete(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            child: const Center(
              child: Icon(Icons.delete_outline, size: 28),
            ),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${fmt.format(meeting.startedAt.toLocal())} '
                '(${formatMegabytesFromBytes(meeting.fileSizeBytes)})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Место: ${meeting.meetingPlace}'),
              Text('Длительность: ${formatDurationSeconds(meeting.durationSeconds)}'),
              Text('Статус: $status'),
              if (progress != null) ...[
                LinearProgressIndicator(value: progress!.fraction),
                const SizedBox(height: 4),
                Text(
                  '${formatMegabytesFromBytes(progress!.sentBytes)} '
                  'из ${formatMegabytesFromBytes(progress!.totalBytes)} '
                  '(${((progress!.fraction) * 100).toStringAsFixed(0)}%)'
                  '${progress!.etaSeconds != null ? ' · ~${progress!.etaSeconds} с' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              Row(
                children: [
                  TextButton(onPressed: onPlay, child: const Text('Прослушать')),
                  if (meeting.uploadStatus != LocalUploadStatus.uploaded)
                    TextButton(onPressed: onUpload, child: const Text('Выгрузить')),
                  TextButton(
                    onPressed: confirmDelete,
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(LocalUploadStatus s) {
    switch (s) {
      case LocalUploadStatus.uploaded:
        return 'Выгружена';
      case LocalUploadStatus.uploading:
        return 'Выгружается…';
      case LocalUploadStatus.error:
        return 'Ошибка';
      case LocalUploadStatus.notUploaded:
        return 'Не выгружена';
    }
  }
}
