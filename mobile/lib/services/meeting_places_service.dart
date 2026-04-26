import 'package:dio/dio.dart';

import '../data/meeting_place_model.dart';
import '../data/meeting_places_repository.dart';
import '../data/settings_repository.dart';

class MeetingPlacesUpdateResult {
  const MeetingPlacesUpdateResult({
    required this.added,
    required this.removed,
    required this.changed,
  });

  final int added;
  final int removed;
  final int changed;
}

class MeetingPlacesService {
  MeetingPlacesService(this._dio, this._settings, this._repo);

  final Dio _dio;
  final SettingsRepository _settings;
  final MeetingPlacesRepository _repo;

  String _normalizeBase(String raw) => raw.trim().replaceAll(RegExp(r'/$'), '');

  Future<void> ensureServerReachable() async {
    final base = _normalizeBase(await _settings.getServerUrl());
    if (base.isEmpty) {
      throw StateError('В настройках укажите адрес сервера');
    }
    await _dio.get('$base/health');
  }

  Future<MeetingPlacesUpdateResult> refreshFromServer() async {
    final base = _normalizeBase(await _settings.getServerUrl());
    if (base.isEmpty) {
      throw StateError('В настройках укажите адрес сервера');
    }

    final before = await _repo.listUnsorted();
    final resp = await _dio.get<Map<String, dynamic>>('$base/api/v1/meeting-places');
    final data = resp.data ?? const <String, dynamic>{};
    final list = (data['places'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final next = list
        .map(
          (e) => MeetingPlace(
            id: (e['id'] as num).toInt(),
            name: (e['name'] as String).trim(),
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final beforeById = {for (final p in before) p.id: p};
    final nextById = {for (final p in next) p.id: p};

    var added = 0;
    var removed = 0;
    var changed = 0;

    for (final id in nextById.keys) {
      final b = beforeById[id];
      if (b == null) {
        added++;
      } else if (b.name != nextById[id]!.name) {
        changed++;
      }
    }
    for (final id in beforeById.keys) {
      if (!nextById.containsKey(id)) removed++;
    }

    await _repo.replaceAll(next);
    return MeetingPlacesUpdateResult(added: added, removed: removed, changed: changed);
  }
}

