/// **Phase 0 completion pass.** First file in `core/utils/` — a folder
/// the Architecture doc's Section 1 names ("ULID gen, debouncing,
/// connectivity helpers") but that never existed in this tree until
/// now. This particular utility exists because
/// ImportProductsFromCsv needs one and nothing in this codebase
/// parses CSV *in* — csv_export_service.dart only ever writes it, and
/// deliberately hand-rolls that writing rather than pulling in a
/// package (see that file's own header comment on why: RFC 4180
/// mechanics are "generic, uncontroversial"). Parsing is the same kind
/// of uncontroversial mechanics, so it gets the same treatment here —
/// no new pubspec dependency for something this self-contained.
///
/// Handles what a shop owner's spreadsheet export realistically
/// contains: comma-separated fields, double-quoted fields (so a value
/// can itself contain a comma), an escaped `""` for a literal quote
/// inside a quoted field, both CRLF and bare LF line endings, and a
/// leading UTF-8 BOM (common from Excel's own "Save As CSV" on
/// Windows) — the same BOM-strip the backend's own `_parse_csv`
/// already does via `utf-8-sig`, mirrored here for the same reason:
/// without it, the first header's name would silently come out
/// prefixed with an invisible character and never match anything.
class CsvParser {
  const CsvParser();

  static const _bom = '\uFEFF';

  /// Splits raw CSV text into rows of raw string cells. Blank lines
  /// (no content at all between two line breaks) are skipped, matching
  /// the backend Excel path's own "skip entirely blank rows" behavior
  /// — the CSV path there doesn't need the same guard only because
  /// Python's `csv.DictReader` already skips them by construction, not
  /// because blank rows are meaningful to keep.
  List<List<String>> parse(String content) {
    final text = content.startsWith(_bom) ? content.substring(1) : content;
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var sawAnyFieldContentOnThisRow = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      if (sawAnyFieldContentOnThisRow || row.length > 1 || row.first.isNotEmpty) {
        rows.add(row);
      }
      row = [];
      sawAnyFieldContentOnThisRow = false;
    }

    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(char);
        sawAnyFieldContentOnThisRow = true;
        i++;
        continue;
      }

      switch (char) {
        case '"':
          inQuotes = true;
          sawAnyFieldContentOnThisRow = true;
          i++;
        case ',':
          endField();
          sawAnyFieldContentOnThisRow = true;
          i++;
        case '\r':
          // Peek past an optional following \n so CRLF collapses to one
          // row break, not two.
          if (i + 1 < text.length && text[i + 1] == '\n') {
            i++;
          }
          endRow();
          i++;
        case '\n':
          endRow();
          i++;
        default:
          field.write(char);
          sawAnyFieldContentOnThisRow = true;
          i++;
      }
    }
    // Final row, if the file didn't end on a line break.
    if (field.isNotEmpty || sawAnyFieldContentOnThisRow || row.isNotEmpty) {
      endRow();
    }

    return rows;
  }

  /// Convenience wrapper matching the backend's own `_parse_csv` return
  /// shape (headers, list-of-dict-rows) — ImportProductsFromCsv reads
  /// columns by name, not position, same as the backend does, so a
  /// column reorder in someone's spreadsheet doesn't break the import.
  /// Header matching is case-insensitive and trims whitespace, same as
  /// [_require_headers]'s own `.lower()` comparison on the backend.
  /// Duplicate headers: last one wins, since a Dart Map can't hold two
  /// values under one key anyway — not a case the backend handles any
  /// more gracefully either.
  ({List<String> headers, List<Map<String, String>> rows}) parseWithHeaders(String content) {
    final rawRows = parse(content);
    if (rawRows.isEmpty) {
      return (headers: const [], rows: const []);
    }
    final headers = rawRows.first.map((h) => h.trim()).toList();
    final dataRows = <Map<String, String>>[];
    for (final raw in rawRows.skip(1)) {
      final map = <String, String>{};
      for (var col = 0; col < headers.length; col++) {
        map[headers[col]] = col < raw.length ? raw[col].trim() : '';
      }
      dataRows.add(map);
    }
    return (headers: headers, rows: dataRows);
  }
}
