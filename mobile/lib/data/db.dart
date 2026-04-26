import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'recordsbl.db');
  return openDatabase(
    path,
    version: 3,
    onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE meetings (
          id TEXT PRIMARY KEY,
          file_path TEXT NOT NULL,
          meeting_place TEXT NOT NULL,
          started_at TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          upload_status TEXT NOT NULL,
          uploaded_bytes INTEGER NOT NULL DEFAULT 0,
          file_size_bytes INTEGER NOT NULL,
          server_upload_id TEXT,
          s3_key TEXT,
          completed_parts TEXT,
          last_error TEXT,
          user_login TEXT NOT NULL,
          server_base_url TEXT NOT NULL,
          recording_offset_ms INTEGER NOT NULL DEFAULT 0,
          incomplete INTEGER NOT NULL DEFAULT 0,
          next_retry_at TEXT,
          retry_attempt INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE meeting_places (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
        )
      ''');

      await db.insert('meeting_places', {'id': 1, 'name': 'Вне офиса (ЦО)'});
      await db.insert('meeting_places', {'id': 2, 'name': 'Переговорная "Байкал"'});
      await db.insert('meeting_places', {'id': 3, 'name': 'Переговорная "Белуха"'});
      await db.insert('meeting_places', {'id': 4, 'name': 'Переговорная "Катунь"'});
      await db.insert('meeting_places', {'id': 5, 'name': 'Переговорная "Конференцзал"'});
      await db.insert('meeting_places', {'id': 6, 'name': 'Переговорная "Красная поляна"'});
      await db.insert('meeting_places', {'id': 7, 'name': 'Переговорная "Москва"'});
      await db.insert('meeting_places', {'id': 8, 'name': 'Переговорная "Саяны"'});
      await db.insert('meeting_places', {'id': 9, 'name': 'Переговорная "Север"'});
      await db.insert('meeting_places', {'id': 10, 'name': 'Переговорная "Юг"'});
      await db.insert('meeting_places', {'id': 11, 'name': 'Переговорная "Запад"'});
      await db.insert('meeting_places', {'id': 12, 'name': 'Переговорная "Ярославль"'});
    },
    onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) {
        await db.execute(
          'ALTER TABLE meetings ADD COLUMN next_retry_at TEXT',
        );
        await db.execute(
          'ALTER TABLE meetings ADD COLUMN retry_attempt INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (oldV < 3) {
        await db.execute('''
          CREATE TABLE meeting_places (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
          )
        ''');
        await db.insert('meeting_places', {'id': 1, 'name': 'Вне офиса (ЦО)'});
        await db.insert('meeting_places', {'id': 2, 'name': 'Переговорная "Байкал"'});
        await db.insert('meeting_places', {'id': 3, 'name': 'Переговорная "Белуха"'});
        await db.insert('meeting_places', {'id': 4, 'name': 'Переговорная "Катунь"'});
        await db.insert('meeting_places', {'id': 5, 'name': 'Переговорная "Конференцзал"'});
        await db.insert('meeting_places', {'id': 6, 'name': 'Переговорная "Красная поляна"'});
        await db.insert('meeting_places', {'id': 7, 'name': 'Переговорная "Москва"'});
        await db.insert('meeting_places', {'id': 8, 'name': 'Переговорная "Саяны"'});
        await db.insert('meeting_places', {'id': 9, 'name': 'Переговорная "Север"'});
        await db.insert('meeting_places', {'id': 10, 'name': 'Переговорная "Юг"'});
        await db.insert('meeting_places', {'id': 11, 'name': 'Переговорная "Запад"'});
        await db.insert('meeting_places', {'id': 12, 'name': 'Переговорная "Ярославль"'});
      }
    },
  );
}
