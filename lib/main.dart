import 'package:dargon2_flutter/dargon2_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

/// Entry point. Deliberately thin — every real decision (DB open order,
/// DI wiring, WorkManager registration) lives in bootstrap.dart per
/// Architecture Section 1's stated split between main.dart and
/// app/bootstrap.dart, so this file never grows into a dumping ground as
/// more init steps are added over time.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required by dargon2_flutter itself (see its README/API docs): the
  // Argon2 hashing calls used by PasswordHasher and PinHasher hang
  // indefinitely — no error, no completion — if this isn't called
  // before they're first used. Must run before bootstrap(), since
  // bootstrap() constructs AuthRepositoryImpl with an Argon2PasswordHasher.
  DArgon2Flutter.init();

  // bootstrap() opens the Drift database and initializes secure storage
  // and the API client — all BEFORE the widget tree is built, per
  // Architecture Section 12's launch-time requirement: nothing on the
  // splash screen should be waiting on a network call, but the local
  // database genuinely does need to be open before the first screen can
  // read from it. bootstrap() opens the DB asynchronously and returns
  // the container with it already wired in, rather than the first
  // screen discovering a null database reference.
  //
  // WorkManager background-sync registration (Architecture Section 8)
  // is NOT part of bootstrap() yet — that's real, undone work belonging
  // to the sync engine, which doesn't exist in this phase. An earlier
  // draft of this comment claimed it was already handled here; it
  // wasn't, and the comment was corrected to stop overstating what the
  // code actually does.
  final container = await bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FulusApp(),
    ),
  );
}
