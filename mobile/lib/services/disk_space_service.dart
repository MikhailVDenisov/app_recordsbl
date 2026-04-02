import 'dart:io';

/// Проверка свободного места (МБ).
///
/// На Android — эвристика через `df` для `/data` (без плагина [disk_space]).
/// На iOS без нативного API точного значения нет → [DiskWarning.okUnknown].
class DiskSpaceService {
  DiskSpaceService._();

  static Future<double?> freeMegabytes() async {
    try {
      if (Platform.isAndroid) {
        final r = await Process.run('df', ['-Pk', '/data']);
        if (r.exitCode == 0) {
          for (final line in (r.stdout as String).split('\n')) {
            if (!line.contains('/data')) continue;
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final availKb = int.tryParse(parts[3]);
              if (availKb != null) return availKb / 1024;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<DiskWarning> check() async {
    final mb = await freeMegabytes();
    if (mb == null) return DiskWarning.okUnknown;
    if (mb < 10) return DiskWarning.critical;
    if (mb < 100) return DiskWarning.warn;
    return DiskWarning.ok;
  }
}

enum DiskWarning {
  ok,
  okUnknown,
  warn,
  critical,
}
