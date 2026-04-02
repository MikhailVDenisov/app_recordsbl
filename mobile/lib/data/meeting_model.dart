enum LocalUploadStatus {
  notUploaded,
  uploading,
  uploaded,
  error,
}

class Meeting {
  Meeting({
    required this.id,
    required this.filePath,
    required this.meetingPlace,
    required this.startedAt,
    required this.durationSeconds,
    required this.uploadStatus,
    required this.uploadedBytes,
    required this.fileSizeBytes,
    this.serverUploadId,
    this.s3Key,
    this.completedPartsJson,
    this.lastError,
    required this.userLogin,
    required this.serverBaseUrl,
    this.recordingOffsetMs = 0,
    this.incomplete = false,
    this.nextRetryAt,
    this.retryAttempt = 0,
  });

  final String id;
  final String filePath;
  final String meetingPlace;
  final DateTime startedAt;
  final int durationSeconds;
  final LocalUploadStatus uploadStatus;
  final int uploadedBytes;
  final int fileSizeBytes;
  final String? serverUploadId;
  final String? s3Key;
  final String? completedPartsJson;
  final String? lastError;
  final String userLogin;
  final String serverBaseUrl;
  final int recordingOffsetMs;
  final bool incomplete;
  final DateTime? nextRetryAt;
  final int retryAttempt;

  Meeting copyWith({
    LocalUploadStatus? uploadStatus,
    int? uploadedBytes,
    int? fileSizeBytes,
    String? serverUploadId,
    String? s3Key,
    String? completedPartsJson,
    String? lastError,
    int? durationSeconds,
    bool? incomplete,
    DateTime? nextRetryAt,
    int? retryAttempt,
  }) {
    return Meeting(
      id: id,
      filePath: filePath,
      meetingPlace: meetingPlace,
      startedAt: startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      serverUploadId: serverUploadId ?? this.serverUploadId,
      s3Key: s3Key ?? this.s3Key,
      completedPartsJson: completedPartsJson ?? this.completedPartsJson,
      lastError: lastError,
      userLogin: userLogin,
      serverBaseUrl: serverBaseUrl,
      recordingOffsetMs: recordingOffsetMs,
      incomplete: incomplete ?? this.incomplete,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      retryAttempt: retryAttempt ?? this.retryAttempt,
    );
  }

  static LocalUploadStatus _statusFrom(String s) {
    switch (s) {
      case 'uploading':
        return LocalUploadStatus.uploading;
      case 'uploaded':
        return LocalUploadStatus.uploaded;
      case 'error':
        return LocalUploadStatus.error;
      default:
        return LocalUploadStatus.notUploaded;
    }
  }

  static String statusToString(LocalUploadStatus s) {
    switch (s) {
      case LocalUploadStatus.uploading:
        return 'uploading';
      case LocalUploadStatus.uploaded:
        return 'uploaded';
      case LocalUploadStatus.error:
        return 'error';
      case LocalUploadStatus.notUploaded:
        return 'not_uploaded';
    }
  }

  static Meeting fromMap(Map<String, Object?> m) {
    return Meeting(
      id: m['id']! as String,
      filePath: m['file_path']! as String,
      meetingPlace: m['meeting_place']! as String,
      startedAt: DateTime.parse(m['started_at']! as String),
      durationSeconds: m['duration_seconds']! as int,
      uploadStatus: _statusFrom(m['upload_status']! as String),
      uploadedBytes: (m['uploaded_bytes'] as int?) ?? 0,
      fileSizeBytes: m['file_size_bytes']! as int,
      serverUploadId: m['server_upload_id'] as String?,
      s3Key: m['s3_key'] as String?,
      completedPartsJson: m['completed_parts'] as String?,
      lastError: m['last_error'] as String?,
      userLogin: m['user_login']! as String,
      serverBaseUrl: m['server_base_url']! as String,
      recordingOffsetMs: (m['recording_offset_ms'] as int?) ?? 0,
      incomplete: ((m['incomplete'] as int?) ?? 0) == 1,
      nextRetryAt: m['next_retry_at'] != null
          ? DateTime.tryParse(m['next_retry_at']! as String)
          : null,
      retryAttempt: (m['retry_attempt'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'meeting_place': meetingPlace,
      'started_at': startedAt.toIso8601String(),
      'duration_seconds': durationSeconds,
      'upload_status': statusToString(uploadStatus),
      'uploaded_bytes': uploadedBytes,
      'file_size_bytes': fileSizeBytes,
      'server_upload_id': serverUploadId,
      's3_key': s3Key,
      'completed_parts': completedPartsJson,
      'last_error': lastError,
      'user_login': userLogin,
      'server_base_url': serverBaseUrl,
      'recording_offset_ms': recordingOffsetMs,
      'incomplete': incomplete ? 1 : 0,
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'retry_attempt': retryAttempt,
    };
  }
}
