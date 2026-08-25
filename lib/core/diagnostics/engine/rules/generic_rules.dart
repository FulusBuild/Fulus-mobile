import '../../../errors/failure.dart';
import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// Catches the shape this app's own guard clauses already throw in
/// (verified directly — e.g. `CartCubit.addProduct`'s
/// `StateError('That product is no longer available.')`): something
/// the app expected to still exist no longer does. Message-matched
/// rather than tied to one specific exception type, since this same
/// pattern is thrown as a plain [StateError] in several places across
/// this codebase, not through one shared exception class.
class MissingEntityRule extends DiagnosticRule {
  const MissingEntityRule();

  @override
  String get name => 'state.missingEntity';

  static const _phrases = [
    'no longer available',
    'no longer exists',
    'does not exist',
    'not found',
  ];

  @override
  bool matches(DiagnosticSignal signal) {
    if (signal.error is! StateError && signal.error is! ArgumentError) return false;
    final text = signal.effectiveErrorText.toLowerCase();
    return _phrases.any(text.contains);
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'Something this action expected to still be there — a '
            'product, customer, or other record — was no longer found, most '
            'likely because it was changed or removed elsewhere first.',
        confidence: DiagnosticConfidence.medium,
      );
}

/// [ValidationFailure] reaching a diagnostic capture point at all is
/// already the unusual case — ordinarily one is caught right at its own
/// form (see settings_main_screen.dart's `on Failure catch (f)` for the
/// normal path) and never reaches here. When it does, it's still
/// legitimate input rejection, not a technical fault — [severityOverride]
/// keeps it at `warning` rather than whatever the call site defaulted
/// to, and the field errors themselves become evidence rather than
/// being restated in prose.
class ValidationRejectionRule extends DiagnosticRule {
  const ValidationRejectionRule();

  @override
  String get name => 'validation.fieldRejection';

  @override
  bool matches(DiagnosticSignal signal) => signal.error is ValidationFailure;

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'One or more fields failed validation before this could be '
            'submitted.',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) {
    final error = signal.error;
    if (error is! ValidationFailure) return const [];
    return error.fieldErrors.entries.map((e) => EvidenceItem(e.key, e.value)).toList();
  }

  @override
  DiagnosticSeverity? severityOverride(DiagnosticSignal signal) => DiagnosticSeverity.warning;
}

/// Same reasoning as [ValidationRejectionRule] above, for a deliberate
/// business-rule rejection (insufficient stock, a sale total that would
/// go negative) rather than a field-level one.
class BusinessRuleRejectionRule extends DiagnosticRule {
  const BusinessRuleRejectionRule();

  @override
  String get name => 'validation.businessRuleRejection';

  @override
  bool matches(DiagnosticSignal signal) => signal.error is BusinessRuleFailure;

  @override
  DiagnosticCause apply(DiagnosticSignal signal) {
    final error = signal.error as BusinessRuleFailure;
    return DiagnosticCause(
      description: 'Rejected by a business rule: ${error.message}',
      confidence: DiagnosticConfidence.high,
    );
  }

  @override
  DiagnosticSeverity? severityOverride(DiagnosticSignal signal) => DiagnosticSeverity.warning;
}

/// A failure during app startup gets no more specific evidence than
/// "this happened before the app was ready" unless a more specific rule
/// above (database, file system) already matched first — the value
/// here is purely in the category/confidence combination itself,
/// signaling "look here first" to a developer rather than treating a
/// startup crash as an ordinary in-session error.
class StartupFailureRule extends DiagnosticRule {
  const StartupFailureRule();

  @override
  String get name => 'startup.generic';

  @override
  bool matches(DiagnosticSignal signal) => signal.categoryHint == DiagnosticCategory.startup;

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'Fulus failed during startup, before the first screen was '
            'ready. See the technical details for the specific error.',
        confidence: DiagnosticConfidence.medium,
      );
}

/// The app-defined-type rules — checked early, since [ValidationFailure]/
/// [BusinessRuleFailure]/[StateError] are unambiguous once matched at
/// all and shouldn't be shadowed by a more generic rule elsewhere.
const List<DiagnosticRule> genericRules = [
  ValidationRejectionRule(),
  BusinessRuleRejectionRule(),
  MissingEntityRule(),
];

/// Deliberately NOT part of [genericRules] — this is the true last
/// resort, checked by RootCauseEngine only after every category-specific
/// rule (database, file system, network...) has already had a chance to
/// give a more precise answer, since a startup-time database failure
/// should still be diagnosed as a database failure first.
const DiagnosticRule startupFallbackRule = StartupFailureRule();
