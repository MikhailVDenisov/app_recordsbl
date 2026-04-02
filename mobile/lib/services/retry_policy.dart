import '../data/meeting_model.dart';

/// Задержки повтора в минутах: 5 → 15 → 60 (экспоненциально по ТЗ).
DateTime nextRetryTime(int attempt) {
  const delays = [5, 15, 60];
  final idx = attempt.clamp(0, delays.length - 1);
  return DateTime.now().add(Duration(minutes: delays[idx]));
}

Meeting markUploadError(Meeting m, Object e, int attempt) {
  return m.copyWith(
    uploadStatus: LocalUploadStatus.error,
    lastError: e.toString(),
    nextRetryAt: nextRetryTime(attempt),
    retryAttempt: attempt + 1,
  );
}
