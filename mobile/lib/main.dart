import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/meeting_places_repository.dart';
import 'data/meeting_repository.dart';
import 'data/db.dart';
import 'app.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  final repo = MeetingRepository(db);
  final placesRepo = MeetingPlacesRepository(db);

  runApp(
    ProviderScope(
      overrides: [
        meetingRepositoryProvider.overrideWithValue(repo),
        meetingPlacesRepositoryProvider.overrideWithValue(placesRepo),
      ],
      child: const RecordsApp(),
    ),
  );
}
