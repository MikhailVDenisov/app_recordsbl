import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/meeting_repository.dart';
import 'data/db.dart';
import 'app.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  final repo = MeetingRepository(db);

  runApp(
    ProviderScope(
      overrides: [
        meetingRepositoryProvider.overrideWithValue(repo),
      ],
      child: const RecordsApp(),
    ),
  );
}
