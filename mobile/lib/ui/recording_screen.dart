import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format_grouped.dart';
import '../providers.dart';
import '../services/disk_space_service.dart';
import '../services/recording_controller.dart';
import 'app_branding.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  String? _place;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  String _mbLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} МБ';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = ref.read(settingsRepositoryProvider);
      final login = await settings.getLogin() ?? '';
      final server = await settings.getServerUrl();
      await ref.read(recordingControllerProvider.notifier).prepareSession(
            userLogin: login,
            serverBaseUrl: server,
          );
      // Место встречи выбирается пользователем перед стартом записи.
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(recordingControllerProvider);
    final placesAsync = ref.watch(meetingPlacesProvider);
    final placeValue = rec.meetingPlace ?? _place;

    final active = rec.phase == RecordingPhase.recording ||
        rec.phase == RecordingPhase.paused;

    return Scaffold(
      appBar: AppBar(
        title: const AistAppBarTitle(),
      ),
      body: SafeArea(
        child: placesAsync.when(
          data: (places) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            value: placeValue,
                            decoration:
                                const InputDecoration(labelText: 'Место встречи'),
                            hint: const Text('Выберите из списка'),
                            items: places
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.name,
                                    child: Text(e.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              setState(() => _place = v);
                              await ref
                                  .read(recordingControllerProvider.notifier)
                                  .setMeetingPlace(v);
                            },
                          ),
                          const SizedBox(height: 24),
                          Text(
                            rec.phase == RecordingPhase.idle
                                ? 'Готов к записи'
                                : rec.phase == RecordingPhase.recording
                                    ? 'Идёт запись (${_mbLabel(rec.recordedBytes)})'
                                    : 'Пауза (${_mbLabel(rec.recordedBytes)})',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text('Время: ${_fmt(rec.duration)}'),
                          if (rec.warning == DiskWarning.warn)
                            const Text(
                              'Внимание: на диске меньше 100 МБ свободного места.',
                              style: TextStyle(color: Colors.orange),
                            ),
                          if (rec.blockedByDisk)
                            const Text(
                              'Запись остановлена: меньше 10 МБ на диске.',
                              style: TextStyle(color: Colors.red),
                            ),
                          const SizedBox(height: 16),
                          Text('Уровень (RMS): ${rec.rms.toStringAsFixed(4)}'),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 12,
                              value: (rec.rms * 4).clamp(0, 1),
                            ),
                          ),
                          const Spacer(),
                          if (active)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  rec.freeDiskMb != null
                                      ? 'Свободно: ${formatGroupedMb(rec.freeDiskMb!)} МБ'
                                      : 'Свободно: н/д',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (rec.phase == RecordingPhase.recording)
                                FilledButton.tonal(
                                  onPressed: () async {
                                    await ref
                                        .read(recordingControllerProvider.notifier)
                                        .pause();
                                  },
                                  child: const Text('Пауза'),
                                ),
                              if (rec.phase == RecordingPhase.paused)
                                FilledButton.tonal(
                                  onPressed: () async {
                                    await ref
                                        .read(recordingControllerProvider.notifier)
                                        .resume();
                                  },
                                  child: const Text('Продолжить'),
                                ),
                              FilledButton(
                                onPressed: () async {
                                  if (rec.phase == RecordingPhase.idle) {
                                    if ((_place ?? '').trim().isEmpty) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Выберите место встречи'),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    final ok = await ref
                                        .read(recordingControllerProvider.notifier)
                                        .startRecording();
                                    if (!ok && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Не удалось начать запись'),
                                        ),
                                      );
                                    }
                                  } else {
                                    await ref
                                        .read(recordingControllerProvider.notifier)
                                        .stopAndSave();
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  }
                                },
                                child: Text(
                                  rec.phase == RecordingPhase.idle ? 'Старт' : 'Стоп',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Ошибка: $e')),
        ),
      ),
    );
  }
}
