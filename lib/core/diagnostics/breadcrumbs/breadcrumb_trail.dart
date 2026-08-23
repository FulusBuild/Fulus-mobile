import '../models/breadcrumb.dart';

/// The global, bounded "how did we get here" buffer. One instance lives
/// for the app's whole process lifetime, owned by [DiagnosticLogger] —
/// every `logger.breadcrumb(...)` call anywhere in the app (cart
/// actions, repository stage markers, navigation) appends here, and
/// every captured [DiagnosticEvent] gets a snapshot of whatever's
/// currently in it.
///
/// **What belongs here, per the brief's own rule:** meaningful business
/// and state-transition events — "Product added to cart", "Sale
/// transaction started". **What does NOT**: a breadcrumb per widget
/// rebuild, per frame, or per function call — that's noise that would
/// bury the signal a real failure needs, not help find one. Call sites
/// were chosen deliberately (see the implementation report) rather than
/// scattered everywhere on the theory that more is safer.
///
/// Bounded at [maxEntries] — a fixed-size ring, oldest entries silently
/// dropped once full, so a long-running session (a till open all day)
/// can never grow this without limit. 100 is deliberately generous
/// relative to what any single captured event actually snapshots (see
/// [snapshot]'s own `limit` default) — the buffer keeps more history
/// than any one event needs so a second, closely-following failure
/// still has real context to draw from, not an empty trail because the
/// first failure's own capture already consumed it (snapshotting never
/// removes entries).
class BreadcrumbTrail {
  BreadcrumbTrail({this.maxEntries = 100});

  final int maxEntries;

  final List<Breadcrumb> _entries = [];

  void add(String message, {String? category, Map<String, String>? data}) {
    _entries.add(Breadcrumb(message: message, category: category, data: data));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// The most recent [limit] breadcrumbs, oldest-first (matching the
  /// detail screen's own "Recent activity" reading order). Defaults to
  /// 30 — enough to show a real sequence without the detail screen's
  /// "Recent activity" section itself becoming the thing that needs
  /// scrolling.
  List<Breadcrumb> snapshot({int limit = 30}) {
    if (_entries.length <= limit) return List.unmodifiable(_entries);
    return List.unmodifiable(_entries.sublist(_entries.length - limit));
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}
