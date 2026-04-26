import 'package:sqflite/sqflite.dart';

import 'meeting_place_model.dart';

class MeetingPlacesRepository {
  MeetingPlacesRepository(this._db);

  final Database _db;

  Future<List<MeetingPlace>> list() async {
    final rows = await _db.query('meeting_places', orderBy: 'name ASC');
    return rows.map(MeetingPlace.fromMap).toList();
  }

  Future<List<MeetingPlace>> listUnsorted() async {
    final rows = await _db.query('meeting_places', orderBy: 'id ASC');
    return rows.map(MeetingPlace.fromMap).toList();
  }

  Future<void> replaceAll(List<MeetingPlace> next) async {
    await _db.transaction((txn) async {
      await txn.delete('meeting_places');
      for (final p in next) {
        await txn.insert(
          'meeting_places',
          p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}

