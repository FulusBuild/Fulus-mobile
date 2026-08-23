/// A single meaningful application event — "Product added to cart",
/// "Sale transaction started" — recorded by [BreadcrumbTrail] and, when
/// a [DiagnosticEvent] is captured, snapshotted into that event's own
/// `breadcrumbs` list so a developer can see the sequence that led to a
/// failure, not just the failure itself.
///
/// Deliberately narrow: a timestamp, a message, an optional category
/// tag, and a small flat data map — enough to reconstruct "what was
/// happening", not a general-purpose logging record. See
/// BreadcrumbTrail's own header comment for what belongs here versus
/// what doesn't (noise like every widget rebuild never should).
class Breadcrumb {
  Breadcrumb({
    required this.message,
    DateTime? timestamp,
    this.category,
    Map<String, String>? data,
  })  : timestamp = timestamp ?? DateTime.now(),
        data = data == null ? const {} : Map.unmodifiable(data);

  final DateTime timestamp;

  /// Plain-language, e.g. "Product added to cart" — written the same
  /// way a developer would narrate the sequence out loud, not a code
  /// identifier.
  final String message;

  /// A short free-text grouping, e.g. "cart", "sale", "sync" — looser
  /// than [DiagnosticCategory] on purpose: a breadcrumb narrates a UI or
  /// business event, which doesn't always map cleanly onto the failure
  /// taxonomy an *error* is classified under.
  final String? category;

  /// Small, redaction-checked key/value context (e.g. `{'productId':
  /// '184'}`) — never raw request/response bodies or full entities.
  /// Passed through [DiagnosticRedactor] before it is ever persisted or
  /// shared, same as evidence.
  final Map<String, String> data;

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        if (category != null) 'category': category,
        if (data.isNotEmpty) 'data': data,
      };

  factory Breadcrumb.fromJson(Map<String, Object?> json) {
    final rawData = json['data'];
    return Breadcrumb(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      message: json['message'] as String? ?? '',
      category: json['category'] as String?,
      data: rawData is Map
          ? rawData.map((key, value) => MapEntry(key.toString(), value.toString()))
          : null,
    );
  }

  @override
  String toString() => '[$timestamp] $message';
}
