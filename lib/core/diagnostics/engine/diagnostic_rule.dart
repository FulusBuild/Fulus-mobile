import '../models/diagnostic_enums.dart';
import '../models/diagnostic_event.dart';
import 'diagnostic_signal.dart';

/// One deterministic cause-classification rule. Every rule in
/// engine/rules/ implements exactly this: a yes/no [matches] predicate
/// examined in priority order by [RootCauseEngine], and an [apply] that
/// only ever runs after [matches] already returned true.
///
/// Deliberately two separate methods rather than one that returns a
/// nullable result — keeps a rule's matching *condition* readable on
/// its own, separately from the cause text it produces, which is what
/// engine/rules/*_test.dart exercises independently (a test can assert
/// "this signal matches" without caring yet what the cause text says).
///
/// **No rule here may guess.** Per the brief's own explicit requirement
/// ("do not invent causes... say UNKNOWN rather than inventing a
/// cause"), a rule that isn't genuinely confident should not exist —
/// [RootCauseEngine.classify] already supplies [DiagnosticCause.unknown]
/// as the outcome when nothing matches, which is the correct behavior
/// for evidence a rule can't account for, not a gap to paper over with
/// a lower-confidence guess.
abstract class DiagnosticRule {
  const DiagnosticRule();

  /// A short, stable, human-readable name for this rule — shown nowhere
  /// in the product UI, but useful in tests and in a future debug view
  /// that wants to say which rule fired.
  String get name;

  bool matches(DiagnosticSignal signal);

  /// Only ever called immediately after [matches] returned true for the
  /// same [signal] — implementations may assume that.
  DiagnosticCause apply(DiagnosticSignal signal);

  /// Evidence bullets specific to this rule's own reasoning, appended
  /// after the signal's own [DiagnosticSignal.context] entries. Most
  /// rules can leave this as the default (no rule-specific evidence
  /// beyond what the call site already supplied via context) —
  /// overridden only where the rule itself derives something new (e.g.
  /// "Constraint: FOREIGN KEY", read off the exception, not something
  /// any call site would already know to pass in).
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) => const [];

  /// Almost always left at the default (`null` = "no opinion, use
  /// whatever severity the call site captured this at"). Overridden
  /// only by the handful of rules (ordinary input validation, an
  /// already-user-facing business-rule rejection) that recognize a
  /// signal as routine rather than a real technical problem, so an
  /// expected "cart is empty" guard doesn't sit in the log reading as
  /// gravely as an actual database corruption would.
  DiagnosticSeverity? severityOverride(DiagnosticSignal signal) => null;
}
