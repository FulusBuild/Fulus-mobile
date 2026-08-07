import '../entities/search_result.dart';
import '../repositories/search_repository.dart';

/// Architecture Section 1's folder structure names `domain/usecases/` —
/// "one class per meaningful action: CreateSale, RecordStockIn,
/// ApproveDiscount" — as an intended part of this codebase's structure;
/// no file existed there yet in the checkpoint this stage started from
/// (no feature has needed one yet — Stage 4 through Stage 12's
/// repositories have all been simple enough to call directly). This is
/// the first one, fulfilling the folder's already-stated intent rather
/// than inventing a new convention.
///
/// A thin pass-through today (search_repository_impl.dart already does
/// all the real work) — kept as its own usecase class anyway, rather
/// than having a future search UI depend on SearchRepository directly,
/// specifically so Architecture's own testing strategy applies here too:
/// "every domain/usecases/ class tested with a fake/in-memory repository,
/// no Drift or Dio" (Section 1), which a UI-layer widget test calling
/// SearchRepository directly wouldn't cleanly get.
class GlobalSearch {
  GlobalSearch({required SearchRepository searchRepository})
      : _searchRepository = searchRepository;

  final SearchRepository _searchRepository;

  Future<SearchResults> call(String query, {int limitPerModule = 5}) {
    return _searchRepository.search(query, limitPerModule: limitPerModule);
  }
}
