import '../models/diagnostic_event.dart';
import 'diagnostic_rule.dart';
import 'diagnostic_signal.dart';
import 'rules/auth_rules.dart';
import 'rules/database_rules.dart';
import 'rules/filesystem_rules.dart';
import 'rules/generic_rules.dart';
import 'rules/network_rules.dart';
import 'rules/sync_rules.dart';

/// The classification result for one [DiagnosticSignal] — everything
/// [DiagnosticLogger] needs to finish building a [DiagnosticEvent], plus
/// the name of whichever rule produced it (for tests, and for a future
/// debug view — never shown in the ordinary product UI).
class DiagnosticClassification {
  const DiagnosticClassification({
    required this.cause,
    required this.evidence,
    this.severityOverride,
    this.matchedRuleName,
  });

  final DiagnosticCause cause;
  final List<EvidenceItem> evidence;
  final DiagnosticSeverity? severityOverride;
  final String? matchedRuleName;
}

/// Deterministic, rule-based root-cause classification — explicitly NOT
/// AI/LLM-based, per the brief's own repeated requirement. Every rule
/// this runs is plain Dart control flow over [DiagnosticSignal]; the
/// entire decision is reproducible and testable without a model call
/// anywhere in the path.
///
/// **Ordering is deliberate and matters**: rules built on this app's own
/// defined exception types ([ValidationFailure], [AuthFailure], and so
/// on — [genericRules]/[authRules]) run first, since a match against a
/// specific, app-defined type is unambiguous. Category-specific rules
/// (database, network, sync, file system) run next, each already
/// ordered internally from most to least specific (see each rules file's
/// own list). [startupFallbackRule] runs dead last, deliberately outside
/// every category list — a startup-time database failure should still
/// be diagnosed as a database failure, with "this happened during
/// startup" as context, not the other way around.
///
/// First match wins. If nothing matches, [classify] returns
/// [DiagnosticCause.unknown] — never a lower-confidence guess assembled
/// from partial evidence. See diagnostic_rule.dart's own header comment
/// for why that discipline lives at the rule level too, not just here.
class RootCauseEngine {
  const RootCauseEngine({List<DiagnosticRule>? rules}) : _rules = rules ?? _defaultRules;

  final List<DiagnosticRule> _rules;

  static const List<DiagnosticRule> _defaultRules = [
    ...genericRules,
    ...authRules,
    ...databaseRules,
    ...networkRules,
    ...syncRules,
    ...fileSystemRules,
    startupFallbackRule,
  ];

  DiagnosticClassification classify(DiagnosticSignal signal) {
    for (final rule in _rules) {
      if (rule.matches(signal)) {
        final evidence = [
          ...signal.context.entries.map((e) => EvidenceItem(e.key, e.value)),
          ...rule.evidenceFor(signal),
        ];
        return DiagnosticClassification(
          cause: rule.apply(signal),
          evidence: evidence,
          severityOverride: rule.severityOverride(signal),
          matchedRuleName: rule.name,
        );
      }
    }
    return DiagnosticClassification(
      cause: const DiagnosticCause.unknown(),
      evidence: signal.context.entries.map((e) => EvidenceItem(e.key, e.value)).toList(),
    );
  }
}
