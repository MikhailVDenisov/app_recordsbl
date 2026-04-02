/// Формат `мм:сс`; при длительности от часа — `чч:мм:сс`.
String formatDurationSeconds(int totalSeconds) {
  var s = totalSeconds;
  if (s < 0) s = 0;
  final d = Duration(seconds: s);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:$m:$sec';
  }
  return '$m:$sec';
}

/// Размер файла в мегабайтах для подписей в списке (2 знака после запятой).
String formatMegabytesFromBytes(int bytes) {
  if (bytes <= 0) return '0.00 МБ';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(2)} МБ';
}
