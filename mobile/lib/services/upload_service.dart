import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../data/meeting_model.dart';
import '../data/meeting_repository.dart';
import '../data/settings_repository.dart';

const _chunkSize = 5 * 1024 * 1024;

class UploadProgress {
  UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    this.etaSeconds,
  });

  final int sentBytes;
  final int totalBytes;
  final int? etaSeconds;

  double get fraction =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0, 1);
}

typedef UploadProgressCb = void Function(UploadProgress p);

class UploadService {
  UploadService(this._dio, this._settings);

  final Dio _dio;
  final SettingsRepository _settings;

  static final RegExp _corpLoginRe = RegExp(r'^[A-Za-z0-9-]+\.[A-Za-z0-9-]+$');

  ({String fileName, String contentType}) _uploadMeta(Meeting m) {
    final ext = p.extension(m.filePath).toLowerCase();
    final fileName = '${m.id}${ext.isEmpty ? '.wav' : ext}';
    final contentType = switch (ext) {
      '.flac' => 'audio/flac',
      '.wav' => 'audio/wav',
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      _ => 'application/octet-stream',
    };
    return (fileName: fileName, contentType: contentType);
  }

  /// В записи встречи сохранён URL на момент остановки записи; если там был
  /// localhost (дефолт по умолчанию), а в настройках уже указан сервер — берём из настроек.
  Future<String> _resolveBaseUrl(Meeting meeting) async {
    var base = meeting.serverBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty || _isLoopbackHost(base)) {
      base = (await _settings.getServerUrl()).replaceAll(RegExp(r'/$'), '');
    }
    if (base.isEmpty) {
      throw StateError('Укажите URL сервера в настройках');
    }
    return base;
  }

  bool _isLoopbackHost(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasAuthority) return false;
    final h = u.host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  int _partLength(int part, int total) {
    final start = (part - 1) * _chunkSize;
    final end = (start + _chunkSize > total) ? total : start + _chunkSize;
    return end - start;
  }

  int _bytesAfterPart(int part, int total) {
    var sum = 0;
    final n = (total / _chunkSize).ceil();
    for (var i = 1; i <= part && i <= n; i++) {
      sum += _partLength(i, total);
    }
    return sum;
  }

  Future<void> uploadMeeting({
    required Meeting meeting,
    required MeetingRepository repo,
    UploadProgressCb? onProgress,
  }) async {
    if (meeting.uploadStatus == LocalUploadStatus.uploaded) {
      return;
    }

    final login = (await _settings.getLogin())?.trim() ?? '';
    if (!_corpLoginRe.hasMatch(login)) {
      throw StateError(
        'В настройках укажите логин в сети компании в формате XXX.XX (латиница/цифры/тире; точка обязательна)',
      );
    }
    final configuredServer = (await _settings.getServerUrl()).trim();
    if (configuredServer.isEmpty) {
      throw StateError('В настройках укажите адрес сервера');
    }

    final base = await _resolveBaseUrl(meeting);
    var m = meeting;
    if (m.userLogin != login) {
      m = m.copyWith(userLogin: login);
      await repo.upsert(m);
    }
    if (m.serverBaseUrl.replaceAll(RegExp(r'/$'), '') != base) {
      m = m.copyWith(serverBaseUrl: base);
      await repo.upsert(m);
    }

    final file = File(meeting.filePath);
    if (!await file.exists()) {
      throw StateError('Файл не найден');
    }
    final size = await file.length();
    if (size == 0) throw StateError('Пустой файл');

    final startedAt = DateTime.now();
    void emit(int sentBytes) {
      _emitUploadProgress(onProgress, sentBytes, size, startedAt);
    }

    emit(0);

    if (m.serverUploadId == null || m.s3Key == null) {
      final meta = _uploadMeta(m);
      final reg = await _dio.post<Map<String, dynamic>>(
        '$base/api/v1/meetings/register',
        data: {
          'id': m.id,
          'userLogin': m.userLogin,
          'fileName': meta.fileName,
          'fileSizeBytes': size,
          'contentType': meta.contentType,
          'device': {
            'login': m.userLogin,
            'model': Platform.operatingSystem,
          },
          'recognition': {
            'id': m.id,
            'meetingPlace': m.meetingPlace,
            'startTimestamp': m.startedAt.toUtc().toIso8601String(),
            'durationSeconds': m.durationSeconds,
            'recordingStartOffsetMs': m.recordingOffsetMs,
          },
        },
      );
      final data = reg.data!;
      m = m.copyWith(
        uploadStatus: LocalUploadStatus.uploading,
        serverUploadId: data['uploadId'] as String?,
        s3Key: data['s3Key'] as String?,
        fileSizeBytes: size,
      );
      await repo.upsert(m);
    }

    final partsState = _loadParts(m.completedPartsJson);
    final listResp = await _dio.get<Map<String, dynamic>>(
      '$base/api/v1/meetings/${m.id}/parts',
    );
    final remote = <int, String>{};
    for (final e in (listResp.data!['parts'] as List<dynamic>)) {
      final p = e as Map<String, dynamic>;
      final n = _partNumberFrom(p['PartNumber']);
      final tag = (p['ETag'] as String).replaceAll('"', '');
      remote[n] = tag;
    }
    for (final e in partsState.entries) {
      remote.putIfAbsent(e.key, () => e.value);
    }

    final partCount = (size / _chunkSize).ceil();
    var uploaded = 0;
    for (var p = 1; p <= partCount; p++) {
      if (remote.containsKey(p)) {
        uploaded = _bytesAfterPart(p, size);
      } else {
        break;
      }
    }
    emit(uploaded);

    final raf = await file.open(mode: FileMode.read);
    try {
      for (var p = 1; p <= partCount; p++) {
        if (remote.containsKey(p)) {
          uploaded = _bytesAfterPart(p, size);
          continue;
        }
        final start = (p - 1) * _chunkSize;
        final endExclusive =
            (start + _chunkSize > size) ? size : start + _chunkSize;
        await raf.setPosition(start);
        final buf = await raf.read(endExclusive - start);

        final urlResp = await _dio.post<Map<String, dynamic>>(
          '$base/api/v1/meetings/${m.id}/presign-part',
          data: {'partNumber': p},
        );
        final url = urlResp.data!['url'] as String;
        final partBase = start;
        final put = await _dio.put<List<int>>(
          url,
          data: buf,
          options: Options(
            headers: {'Content-Type': 'application/octet-stream'},
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
          onSendProgress: (sent, total) {
            final cap = partBase + sent;
            final cumulative = cap > size ? size : cap;
            emit(cumulative);
          },
        );
        var etag = put.headers.value('etag') ?? '';
        etag = etag.replaceAll('"', '');
        if (etag.isEmpty) {
          throw StateError('Нет ETag для части $p');
        }
        remote[p] = etag;
        uploaded = _bytesAfterPart(p, size);
        emit(uploaded);

        final json = jsonEncode(
          remote.map((k, v) => MapEntry(k.toString(), v)),
        );
        m = m.copyWith(
          uploadedBytes: uploaded,
          completedPartsJson: json,
          uploadStatus: LocalUploadStatus.uploading,
        );
        await repo.upsert(m);

        await _dio.patch(
          '$base/api/v1/meetings/${m.id}/progress',
          data: {'uploadedBytes': uploaded},
        );
      }
    } finally {
      await raf.close();
    }

    final completeParts = remote.entries
        .map(
          (e) => <String, dynamic>{
            'PartNumber': e.key,
            'ETag': '"${e.value}"',
          },
        )
        .toList()
      ..sort((a, b) => (a['PartNumber'] as int).compareTo(b['PartNumber'] as int));

    await _dio.post(
      '$base/api/v1/meetings/${m.id}/complete',
      data: {'parts': completeParts},
    );

    m = m.copyWith(
      uploadStatus: LocalUploadStatus.uploaded,
      uploadedBytes: size,
    );
    await repo.upsert(m);
    emit(size);
  }

  Map<int, String> _loadParts(String? json) {
    if (json == null || json.isEmpty) return {};
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  void _emitUploadProgress(
    UploadProgressCb? cb,
    int sentBytes,
    int totalBytes,
    DateTime startedAt,
  ) {
    if (cb == null) return;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    int? etaSeconds;
    if (elapsedMs > 400 && sentBytes > 0 && sentBytes < totalBytes) {
      final rate = sentBytes / (elapsedMs / 1000.0);
      if (rate > 1) {
        etaSeconds = ((totalBytes - sentBytes) / rate).ceil();
        if (etaSeconds < 1) etaSeconds = 1;
        if (etaSeconds > 86400) etaSeconds = null;
      }
    }
    cb(UploadProgress(
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      etaSeconds: etaSeconds,
    ));
  }

  int _partNumberFrom(Object? v) {
    if (v == null) throw StateError('PartNumber отсутствует');
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.parse(v.toString());
  }
}
