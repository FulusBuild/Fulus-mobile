import 'dart:convert';
import 'dart:typed_data';

/// Stage 15 — Device Services (Printing).
///
/// Deliberately pure Dart — no Flutter, no platform channel, no
/// Bluetooth/USB import at all — the same "protocol/algorithm stays
/// fully unit-testable, only the transport wiring depends on a
/// platform" split sync_engine.dart already establishes for the sync
/// queue (see that file's own doc comment). ESC/POS itself is a stable,
/// decades-old thermal-printer command language shared across
/// essentially every budget receipt printer sold in this market
/// regardless of brand — building against the spec directly here, once,
/// is what lets BOTH bluetooth_receipt_printer.dart and
/// usb_receipt_printer.dart stay thin (send these exact bytes over
/// whichever transport), rather than each transport re-deriving its own
/// formatting.
///
/// What this class is NOT: a receipt layout engine. Deciding WHAT a
/// receipt says (business name, line items, totals, VAT breakdown) is
/// Stage 9's job (Receipt Engine) — this class only turns already-decided
/// text/formatting instructions into the correct bytes. Reading this
/// file should never be how someone learns what a Fulus Mobile receipt
/// looks like.
///
/// **A real, unresolved constraint, named rather than papered over:**
/// most budget ESC/POS printers default to a single-byte code page
/// (commonly CP437 or a vendor-specific Latin variant), not UTF-8 — the
/// Naira sign (₦, U+20A6) plain-text-encodes fine in Dart but will not
/// print correctly on hardware that hasn't been told to use a code page
/// that includes it, and many budget models simply don't have one that
/// does. This class currently emits raw UTF-8 bytes for [text] and does
/// not attempt code-page negotiation (`ESC t n`) or a "₦" -&gt; "NGN"
/// fallback substitution — that decision belongs with Stage 9 once real
/// receipt content exists to test against real hardware, not fabricated
/// here against no receipt and no physical printer to verify against.
class EscPosCommandBuilder {
  final List<int> _bytes = [];

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  /// `ESC @` — resets the printer to its power-on defaults. The correct
  /// first command for any new print job; without it, formatting state
  /// left over from a previous job (bold still on, alignment still
  /// centered) can leak into this one.
  EscPosCommandBuilder init() {
    _bytes.addAll([_esc, 0x40]);
    return this;
  }

  EscPosCommandBuilder text(
    String value, {
    bool bold = false,
    PrintAlignment align = PrintAlignment.left,
    bool doubleHeight = false,
  }) {
    _align(align);
    _bold(bold);
    _doubleHeight(doubleHeight);
    _bytes.addAll(utf8.encode(value));
    // Reset per-line modifiers after each text() call rather than
    // requiring the caller to explicitly turn bold/double-height back
    // off — a stray unclosed bold that silently bolds the rest of the
    // receipt is a worse default than always resetting and requiring
    // each call to state what IT wants.
    if (bold) _bold(false);
    if (doubleHeight) _doubleHeight(false);
    return this;
  }

  EscPosCommandBuilder newLine([int count = 1]) {
    for (var i = 0; i < count; i++) {
      _bytes.add(_lf);
    }
    return this;
  }

  /// `ESC d n` — feeds n lines without printing anything, the correct
  /// way to leave blank space before a cut (as opposed to n empty
  /// [newLine] text lines, which works but is a less explicit statement
  /// of intent for the same byte sequence a reader has to decode either
  /// way).
  EscPosCommandBuilder feed(int lines) {
    _bytes.addAll([_esc, 0x64, lines.clamp(0, 255)]);
    return this;
  }

  /// A plain horizontal rule of `-` characters — receipts commonly need
  /// a visual divider between sections, and this is the simplest
  /// correct implementation on hardware with no guaranteed line-drawing
  /// character support. [width] should match the printer's character
  /// width for its paper size (32 for 58mm, 48 for 80mm at the default
  /// font — both real, common values, not a single number that's
  /// correct for every printer this app might ever talk to; the caller
  /// supplies it deliberately rather than this class guessing).
  EscPosCommandBuilder divider({int width = 32}) {
    return text('-' * width).newLine();
  }

  /// `GS V 1` — partial cut. Chosen over `GS V 0` (full cut) as the
  /// default because partial cut (leaving a small connecting strip) is
  /// the more widely-supported of the two across budget/clone printer
  /// firmware in this market — a full-cut command silently doing
  /// nothing on hardware that only implements partial cut is a worse
  /// failure mode than a partial cut where a full cut was actually
  /// wanted, since the fallback here still separates the receipt, just
  /// not as cleanly.
  EscPosCommandBuilder cut() {
    _bytes.addAll([_gs, 0x56, 0x01]);
    return this;
  }

  /// A minimal, self-contained payload for Volume 11's "testing" step
  /// after pairing — deliberately NOT a fake receipt (no business name,
  /// no line items: that would misleadingly look like real Stage 9
  /// output on a screen where the owner is only trying to confirm the
  /// printer itself works).
  static Uint8List testPrint() {
    return EscPosCommandBuilder()
        .init()
        .text('Fulus Mobile', align: PrintAlignment.center, bold: true)
        .newLine()
        .text('Printer test — connection OK', align: PrintAlignment.center)
        .newLine(2)
        .feed(3)
        .cut()
        .build();
  }

  Uint8List build() => Uint8List.fromList(_bytes);

  void _align(PrintAlignment align) {
    final n = switch (align) {
      PrintAlignment.left => 0x00,
      PrintAlignment.center => 0x01,
      PrintAlignment.right => 0x02,
    };
    _bytes.addAll([_esc, 0x61, n]);
  }

  void _bold(bool on) {
    _bytes.addAll([_esc, 0x45, on ? 0x01 : 0x00]);
  }

  void _doubleHeight(bool on) {
    // GS ! n — the low nibble controls height multiplier, the high
    // nibble width; 0x11 is "double both," matching what Volume 16's
    // typography scale would call an emphasized/heading line on a
    // receipt (a total, a business name) versus 0x00 for normal body
    // text.
    _bytes.addAll([_gs, 0x21, on ? 0x11 : 0x00]);
  }
}

enum PrintAlignment { left, center, right }
