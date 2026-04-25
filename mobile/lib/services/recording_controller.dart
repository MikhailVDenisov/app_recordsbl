import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../core/meeting_place.dart';
import '../data/meeting_model.dart';
import '../data/meeting_repository.dart';
import 'audio_session_config.dart';
import 'disk_space_service.dart';

const _sampleRate = 24000;
const _channels = 2;

class RecordingState {
  const RecordingState({
    required this.phase,
    this.duration = Duration.zero,
    this.rms = 0,
    this.recordedBytes = 0,
    this.freeDiskMb,
    this.meetingPlace,
    this.meetingId,
    this.warning,
    this.blockedByDisk = false,
  });

  final RecordingPhase phase;
  final Duration duration;
  final double rms;
  /// Накопленный объём PCM (для отображения размера записи).
  final int recordedBytes;
  /// Оценка свободного места (МБ): опрос раздела минус буфер записи в памяти
  /// (до сохранения WAV на диск `df` почти не меняется).
  final double? freeDiskMb;
  final String? meetingPlace;
  final String? meetingId;
  final DiskWarning? warning;
  final bool blockedByDisk;

  RecordingState copyWith({
    RecordingPhase? phase,
    Duration? duration,
    double? rms,
    int? recordedBytes,
    double? freeDiskMb,
    String? meetingPlace,
    String? meetingId,
    DiskWarning? warning,
    bool? blockedByDisk,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      duration: duration ?? this.duration,
      rms: rms ?? this.rms,
      recordedBytes: recordedBytes ?? this.recordedBytes,
      freeDiskMb: freeDiskMb ?? this.freeDiskMb,
      meetingPlace: meetingPlace ?? this.meetingPlace,
      meetingId: meetingId ?? this.meetingId,
      warning: warning ?? this.warning,
      blockedByDisk: blockedByDisk ?? this.blockedByDisk,
    );
  }
}

enum RecordingPhase { idle, recording, paused }

class RecordingController extends StateNotifier<RecordingState> {
  RecordingController(this._repo) : super(const RecordingState(phase: RecordingPhase.idle));

  final MeetingRepository _repo;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<void>? _interruptSub;
  Timer? _rmsTimer;
  Timer? _durationTimer;
  final Stopwatch _segment = Stopwatch();
  Duration _pausedAccum = Duration.zero;
  DateTime? _startedAt;
  final List<double> _rmsWindow = [];
  String? _currentMeetingId;
  String? _currentPlace;
  String? _userLogin;
  String? _serverUrl;
  String? _currentFilePath;
  DateTime? _lastSizePollAt;
  int _lastKnownFileBytes = 0;
  /// Игнорировать прерывания сразу после старта/возобновления (ложные события на Android).
  DateTime? _ignoreInterruptionUntil;

  /// Последнее значение свободного места по `df` (без вычета буфера).
  double? _diskFreeRawMb;

  static const _rmsWindowSize = 3;
  static const _interruptionGrace = Duration(milliseconds: 1500);

  Future<void> prepareSession({
    required String userLogin,
    required String serverBaseUrl,
  }) async {
    _userLogin = userLogin;
    _serverUrl = serverBaseUrl;
    await configureRecordingSession();
    final session = await AudioSession.instance;
    _interruptSub?.cancel();
    _interruptSub = session.interruptionEventStream.listen((e) async {
      final until = _ignoreInterruptionUntil;
      if (until != null && DateTime.now().isBefore(until)) return;
      if (e.begin && state.phase == RecordingPhase.recording) {
        await pause();
      }
    });
  }

  Future<void> setMeetingPlace(String place) async {
    if (!kMeetingPlaces.contains(place)) return;
    _currentPlace = place;
    state = state.copyWith(meetingPlace: place);
  }

  Duration _totalElapsed() => _pausedAccum + _segment.elapsed;

  /// Свободное место с учётом оценки роста файла записи.
  double? _effectiveFreeMegabytes() {
    final raw = _diskFreeRawMb;
    if (raw == null) return null;
    final pendingMb = _lastKnownFileBytes / (1024 * 1024);
    final v = raw - pendingMb;
    return v < 0 ? 0.0 : v;
  }

  Future<void> _pollFileSize() async {
    final path = _currentFilePath;
    if (path == null) return;
    final now = DateTime.now();
    final last = _lastSizePollAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastSizePollAt = now;
    try {
      final f = File(path);
      if (await f.exists()) {
        _lastKnownFileBytes = await f.length();
      }
    } catch (_) {
      // ignore polling errors (file may be locked or not yet created)
    }
  }

  Future<bool> startRecording() async {
    if (state.phase != RecordingPhase.idle) return false;
    final disk = await DiskSpaceService.check();
    if (disk == DiskWarning.critical) {
      state = state.copyWith(warning: disk, blockedByDisk: true);
      return false;
    }
    final hasPerm = await _recorder.hasPermission();
    if (hasPerm != true) return false;

    if (Platform.isAndroid) {
      final n = await Permission.notification.status;
      if (!n.isGranted) {
        await Permission.notification.request();
      }
    }

    _currentPlace ??= kMeetingPlaces.first;
    _currentMeetingId = const Uuid().v4();
    _pausedAccum = Duration.zero;
    _startedAt = DateTime.now();
    _rmsWindow.clear();
    _segment
      ..reset()
      ..start();
    _lastKnownFileBytes = 0;
    _lastSizePollAt = null;

    await configureRecordingSession();

    final id = _currentMeetingId!;
    final dir = await getApplicationDocumentsDirectory();
    final useFlac = !Platform.isIOS;
    final ext = useFlac ? 'flac' : 'wav';
    final path = p.join(dir.path, '$id.$ext');
    _currentFilePath = path;

    await _recorder.start(
      RecordConfig(
        encoder: useFlac ? AudioEncoder.flac : AudioEncoder.wav,
        sampleRate: _sampleRate,
        numChannels: _channels,
        androidConfig: Platform.isAndroid
            ? const AndroidRecordConfig(
                service: AndroidService(
                  title: 'Запись встречи',
                  content: 'Идёт запись — микрофон активен',
                ),
              )
            : const AndroidRecordConfig(),
      ),
      path: path,
    );

    _ampSub?.cancel();
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // Map dBFS to a stable 0..1-ish value for UI; keep it simple and monotonic.
      final v = (a.current + 60) / 60;
      final clamped = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
      _rmsWindow.add(clamped);
      if (_rmsWindow.length > _rmsWindowSize) {
        _rmsWindow.removeAt(0);
      }
    });

    _ignoreInterruptionUntil =
        DateTime.now().add(_interruptionGrace);

    _diskFreeRawMb = await DiskSpaceService.freeMegabytes();

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_pollFileSize());
      state = state.copyWith(
        duration: _totalElapsed(),
        recordedBytes: _lastKnownFileBytes,
        freeDiskMb: _effectiveFreeMegabytes(),
      );
    });

    _rmsTimer?.cancel();
    _rmsTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_rmsWindow.isEmpty) return;
      final avg = _rmsWindow.reduce((a, b) => a + b) / _rmsWindow.length;
      state = state.copyWith(rms: avg);
    });

    state = RecordingState(
      phase: RecordingPhase.recording,
      duration: Duration.zero,
      rms: 0,
      recordedBytes: 0,
      freeDiskMb: _effectiveFreeMegabytes(),
      meetingPlace: _currentPlace,
      meetingId: _currentMeetingId,
      warning: disk == DiskWarning.warn ? disk : null,
    );

    unawaited(_diskWatch());
    return true;
  }

  Future<void> _diskWatch() async {
    while (state.phase == RecordingPhase.recording ||
        state.phase == RecordingPhase.paused) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (state.phase == RecordingPhase.idle) break;

      _diskFreeRawMb = await DiskSpaceService.freeMegabytes();

      final eff = _effectiveFreeMegabytes();
      if (eff != null) {
        if (eff < 10) {
          await _forceStopLowDisk();
          break;
        }
        state = state.copyWith(
          warning: eff < 100 ? DiskWarning.warn : null,
          freeDiskMb: eff,
        );
      } else if (state.phase != RecordingPhase.idle) {
        state = state.copyWith(freeDiskMb: null);
      }
    }
  }

  Future<void> _forceStopLowDisk() async {
    await _finalizeToDisk(incomplete: true);
    state = state.copyWith(
      phase: RecordingPhase.idle,
      blockedByDisk: true,
      warning: DiskWarning.critical,
    );
  }

  Future<void> pause() async {
    if (state.phase != RecordingPhase.recording) return;
    _pausedAccum += _segment.elapsed;
    _segment.reset();
    _durationTimer?.cancel();
    _rmsTimer?.cancel();
    await _recorder.pause();
    state = state.copyWith(
      phase: RecordingPhase.paused,
      duration: _pausedAccum,
      recordedBytes: _lastKnownFileBytes,
      freeDiskMb: _effectiveFreeMegabytes(),
    );
  }

  Future<void> resume() async {
    if (state.phase != RecordingPhase.paused) return;
    _segment.start();
    _ignoreInterruptionUntil =
        DateTime.now().add(_interruptionGrace);
    await _recorder.resume();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_pollFileSize());
      state = state.copyWith(
        duration: _totalElapsed(),
        recordedBytes: _lastKnownFileBytes,
        freeDiskMb: _effectiveFreeMegabytes(),
      );
    });
    _rmsTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_rmsWindow.isEmpty) return;
      final avg = _rmsWindow.reduce((a, b) => a + b) / _rmsWindow.length;
      state = state.copyWith(rms: avg);
    });
    state = state.copyWith(phase: RecordingPhase.recording);
  }

  Future<void> stopAndSave() async {
    if (state.phase == RecordingPhase.idle) return;
    await _finalizeToDisk(incomplete: false);
  }

  Future<void> _finalizeToDisk({required bool incomplete}) async {
    _rmsTimer?.cancel();
    _durationTimer?.cancel();
    await _pcmSub?.cancel();
    await _ampSub?.cancel();
    await _recorder.stop();
    _pcmSub = null;
    _ampSub = null;
    _segment.stop();

    final id = _currentMeetingId!;
    final place = _currentPlace ?? kMeetingPlaces.first;
    final started = _startedAt ?? DateTime.now();
    final duration = _totalElapsed().inSeconds;
    final path = _currentFilePath ?? (p.join((await getApplicationDocumentsDirectory()).path, '$id.flac'));
    final f = File(path);
    final size = await f.length();

    final meeting = Meeting(
      id: id,
      filePath: path,
      meetingPlace: place,
      startedAt: started,
      durationSeconds: duration,
      uploadStatus: LocalUploadStatus.notUploaded,
      uploadedBytes: 0,
      fileSizeBytes: size,
      userLogin: _userLogin ?? 'unknown',
      serverBaseUrl: _serverUrl ?? '',
      recordingOffsetMs: 0,
      incomplete: incomplete,
    );
    await _repo.upsert(meeting);

    _currentMeetingId = null;
    _currentFilePath = null;
    _diskFreeRawMb = null;
    state = const RecordingState(phase: RecordingPhase.idle);
  }

  @override
  void dispose() {
    _rmsTimer?.cancel();
    _durationTimer?.cancel();
    _interruptSub?.cancel();
    _pcmSub?.cancel();
    _ampSub?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
