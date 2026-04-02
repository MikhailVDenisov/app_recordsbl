import 'package:sqflite/sqflite.dart';

import 'meeting_model.dart';

class MeetingRepository {
  MeetingRepository(this._db);

  final Database _db;

  Future<List<Meeting>> listMeetings() async {
    final rows = await _db.query('meetings', orderBy: 'started_at DESC');
    return rows.map(Meeting.fromMap).toList();
  }

  Future<Meeting?> getById(String id) async {
    final rows = await _db.query('meetings', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Meeting.fromMap(rows.first);
  }

  Future<void> upsert(Meeting m) async {
    await _db.insert(
      'meetings',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    await _db.delete('meetings', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Meeting>> pendingRetries(DateTime now) async {
    final rows = await _db.query(
      'meetings',
      where: 'upload_status = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: ['error', now.toIso8601String()],
    );
    return rows.map(Meeting.fromMap).toList();
  }

  Future<List<Meeting>> incompleteMeetings() async {
    final rows = await _db.query(
      'meetings',
      where: 'incomplete = ?',
      whereArgs: [1],
    );
    return rows.map(Meeting.fromMap).toList();
  }
}
