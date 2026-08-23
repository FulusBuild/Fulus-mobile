import '../models/diagnostic_enums.dart';

/// The normalized "everything a rule might need" bag the root-cause
/// engine builds once per capture and hands to every registered rule.
/// Rules never touch the raw caught object directly beyond what's
/// exposed here — keeping the surface a rule can match against small
/// and explicit is what keeps the engine itself easy to reason about
/// and test (engine/rules/*_test.dart construct one of these directly,
/// with no real exception ever needing to be thrown).
class DiagnosticSignal {
  DiagnosticSignal({
    required this.error,
    required this.stackTrace,
    required this.categoryHint,
    this.component,
    this.operation,
    this.failureStage,
    Map<String, String>? context,
    this.isOffline,
  }) : context = context == null ? const {} : Map.unmodifiable(context);

  final Object error;
  final StackTrace stackTrace;

  /// What the call site believes this is — used as the category on the
  /// resulting event when no rule below overrides it, and as one input
  /// several rules match on. Not authoritative on its own: a database
  /// exception surfacing inside a `sales`-hinted operation (exactly the
  /// worked "archived product referenced by cart" example) should still
  /// be diagnosed as a database-constraint failure, not forced into the
  /// caller's own category guess.
  final DiagnosticCategory categoryHint;

  final String? component;
  final String? operation;
  final String? failureStage;

  /// Free-form operation context the call site already knows — Sale
  /// ID, Product ID, "expected: decrease stock by 2", and so on. Rules
  /// read this both to match against (a key like `httpStatus` or
  /// `dioExceptionType`) and to fold into the final event's evidence
  /// list verbatim.
  final Map<String, String> context;

  /// Ambient connectivity at capture time, when the caller bothered to
  /// check (network/sync rules only) — null means "not checked", which
  /// is different from `false` and rules should not conflate the two.
  final bool? isOffline;

  String get errorText => error.toString();
  String get exceptionType => error.runtimeType.toString();

  /// Best-effort unwrap of a wrapped exception's own `.cause`, via
  /// dynamic dispatch rather than a static type check — several
  /// packages this app depends on (Drift among them) wrap an original
  /// exception in their own type across versions in ways this file
  /// can't compile-time-verify the exact shape of. A wrapper with no
  /// such getter just fails the dynamic lookup, caught here, and the
  /// original [error] is used as-is — this can never throw outward.
  Object get effectiveError {
    try {
      final dynamic e = error;
      final cause = e.cause;
      if (cause is Object) return cause;
    } catch (_) {
      // No `.cause` getter on this type — expected for the common case
      // of an exception that was never wrapped in the first place.
    }
    return error;
  }

  String get effectiveErrorText {
    final effective = effectiveError;
    return effective == error ? errorText : '$errorText | ${effective.toString()}';
  }
}
