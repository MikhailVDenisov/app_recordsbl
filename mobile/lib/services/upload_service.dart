import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../data/meeting_model.dart';
import '../data/meeting_repository.dart';

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
  UploadService(this._dio);

  final Dio _dio;

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
    final base = meeting.serverBaseUrl.replaceAll(RegExp(r'/$'), '');
    final file = File(meeting.filePath);
    if (!await file.exists()) {
      throw StateError('Файл не найден');
    }
    final size = await file.length();
    if (size == 0) throw StateError('Пустой файл');

    var m = meeting;
    if (m.serverUploadId == null || m.s3Key == null) {
      final reg = await _dio.post<Map<String, dynamic>>(
        '$base/api/v1/meetings/register',
        data: {
          'id': m.id,
          'userLogin': m.userLogin,
          'fileName': '${m.id}.wav',
          'fileSizeBytes': size,
          'contentType': 'audio/wav',
          'device': {
            'login': m.userLogin,
            'model': Platform.operatingSystem,
            'freeDiskBytes': null,
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
      final n = p['PartNumber'] as int;
      final tag = (p['ETag'] as String).replaceAll('"', '');
      remote[n] = tag;
    }
    for (final e in partsState.entries) {
      remote.putIfAbsent(e.key, () => e.value);
    }

    final partCount = (size / _chunkSize).ceil();
    final raf = await file.open(mode: FileMode.read);
    var uploaded = 0;
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
        final put = await _dio.put<List<int>>(
          url,
          data: buf,
          options: Options(
            headers: {'Content-Type': 'application/octet-stream'},
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        var etag = put.headers.value('etag') ?? '';
        etag = etag.replaceAll('"', '');
        if (etag.isEmpty) {
          throw StateError('Нет ETag для части $p');
        }
        remote[p] = etag;
        uploaded = _bytesAfterPart(p, size);

        final json = jsonEncode(
          remote.map((k, v) => MapEntry(k.toString(), v)),
        );
        m = m.copyWith(
          uploadedBytes: uploaded,
          completedPartsJson: json,
          uploadStatus: LocalUploadStatus.uploading,
        );
        await repo.upsert(m);

        _emitProgress(onProgress, uploaded, size, p, partCount);
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
  }

  Map<int, String> _loadParts(String? json) {
    if (json == null || json.isEmpty) return {};
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  void _emitProgress(
    UploadProgressCb? cb,
    int sent,
    int total,
    int partIndex,
    int partCount,
  ) {
    if (cb == null) return;
    final eta = partIndex < partCount
        ? ((partCount - partIndex) * 2).clamp(1, 3600)
        : 0;
    cb(UploadProgress(sentBytes: sent, totalBytes: total, etaSeconds: eta));
  }
}
