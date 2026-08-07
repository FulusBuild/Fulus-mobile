import '../entities/search_result.dart';

/// Architecture Section 4's repository pattern, applied to Stage 14's
/// cross-entity search. Unlike every other repository in this codebase,
/// this one deliberately spans more than one table — see
/// search_result.dart's own doc comment on why that's still "one
/// repository" rather than three, matching search_service.py's own
/// single global_search entry point on the backend (verified directly
/// by reading it) rather than three separate backend-mirroring
/// repositories.
abstract class SearchRepository {
  /// Empty or whitespace-only [query] returns SearchResults.empty
  /// without touching the database — Volume 5's own product search
  /// already establishes "no query, no results list" as the expected
  /// resting state, not an error.
  Future<SearchResults> search(String query, {int limitPerModule = 5});
}
