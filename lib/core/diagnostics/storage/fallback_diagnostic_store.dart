import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/diagnostic_event.dart';

/// The emergency backstop [DiagnosticLogger] writes to when the primary
/// [DriftDiagnosticStore] write itself fails — which matters
/// specifically because the *error being diagnosed* can itself be a
/// database failure (a full disk, a corrupt file, a locked database).
/// In that exact scenario, trying to persist the diagnostic record by
/// writing into the very database that just failed would either also
/// fail or, worse, silently discard the original error. This class has
/// zero dependency on Drift or the app database for that reason — a
/// plain, independent, append-only file, so it keeps working precisely
/// when the primary store can't.
///
/// Deliberately NOT a [DiagnosticStore] implementation — this is not a
/// second place the UI ever reads from directly. It exists purely as a
/// short-lived overflow buffer: [DiagnosticLogger] drains it into the
/// primary store the moment a primary write succeeds again (see that
/// class's own `_attemptDrainFallback`), so anything sitting here is
/// only ever a transient state, never a permanent second source of
/// truth the rest of the system would need to know about.
///
/// JSON Lines format (one JSON object per line) rather than a single
/// JSON array — an array would require reading, parsing, and rewriting
/// the *entire* file on every single append; JSON Lines needs only an
/// append, which matters when this class's whole reason to exist is
/// staying reliable while something else is already going wrong.
class FallbackDiagnosticStore {
  FallbackDiagnosticStore();

  /// A hard ceiling on how many emergency entries are kept — this path
  /// is meant to bridge a short window until the primary store recovers
  /// or the app restarts, not to become an unbounded second log. Oldest
  /// entries are dropped first once past this ceiling.
  static const _maxEntries = 200;

  File? _cachedFile;

  Future<File> _resolveFile() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/diagnostics');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/fallback_events.jsonl');
    _cachedFile = file;
    return file;
  }

  /// Appends [event] as one JSON line. Returns `true` on success,
  /// `false` on any failure — never throws. A `false` here means the
  /// original application error genuinely could not be recorded
  /// anywhere; DiagnosticLogger's own last resort at that point is a
  /// plain `debugPrint`, which is the one place in this whole system
  /// that isn't itself defensively wrapped, because there is nothing
  /// further to fall back to.
  Future<bool> append(DiagnosticEvent event) async {
    try {
      final file = await _resolveFile();
      final line = jsonEncode(event.toJson());
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      await _trimIfNeeded(file);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _trimIfNeeded(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.length <= _maxEntries) return;
      final trimmed = lines.sublist(lines.length - _maxEntries);
      await file.writeAsString('${trimmed.join('\n')}\n', flush: true);
    } catch (_) {
      // Trimming is housekeeping, not the actual save — a failure here
      // does not mean the append above failed.
    }
  }

  /// Reads every entry currently buffered and clears the file
  /// afterward, in that order — used by DiagnosticLogger to move
  /// anything accumulated here into the primary store once it's
  /// healthy again. Returns an empty list (never throws) if the file is
  /// missing, empty, or unreadable.
  Future<List<DiagnosticEvent>> drainAll() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return const [];
      final lines = await file.readAsLines();
      final events = <DiagnosticEvent>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            events.add(DiagnosticEvent.fromJson(decoded.cast()));
          }
        } catch (_) {
          // One malformed line (a partial write cut off mid-append by
          // a crash, most plausibly) never invalidates the rest of the
          // file.
        }
      }
      await file.writeAsString('', flush: true);
      return events;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> get hasPendingEntries async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return false;
      return (await file.length()) > 0;
    } catch (_) {
      return false;
    }
  }
}
