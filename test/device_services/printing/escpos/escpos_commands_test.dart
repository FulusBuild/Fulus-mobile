import 'package:fulus_mobile/device_services/printing/escpos/escpos_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EscPosCommandBuilder', () {
    test('init() emits ESC @ (0x1B 0x40)', () {
      final bytes = EscPosCommandBuilder().init().build();
      expect(bytes, [0x1B, 0x40]);
    });

    test('text() emits UTF-8 bytes with no formatting bytes when plain', () {
      final bytes = EscPosCommandBuilder().text('Hi').build();
      // text() unconditionally emits three 3-byte headers before the
      // actual text — align, bold, and doubleHeight — regardless of
      // whether bold/doubleHeight were requested; only the RESET call
      // after the text is conditional (see the bold-text test below).
      // ESC a 0 (left align) + ESC E 0 (bold off) + GS ! 0 (double
      // height off), then the UTF-8 bytes themselves.
      expect(
        bytes,
        [
          0x1B, 0x61, 0x00, // align left
          0x1B, 0x45, 0x00, // bold off
          0x1D, 0x21, 0x00, // double height off
          ...'Hi'.codeUnits,
        ],
      );
    });

    test('bold text is turned on, then explicitly back off after', () {
      final bytes = EscPosCommandBuilder().text('B', bold: true).build();
      expect(
        bytes,
        [
          0x1B, 0x61, 0x00, // align left
          0x1B, 0x45, 0x01, // bold on
          0x1D, 0x21, 0x00, // double height off (not requested)
          ...'B'.codeUnits,
          0x1B, 0x45, 0x00, // bold off (reset, since bold was true)
        ],
      );
    });

    test('center alignment emits ESC a 1', () {
      final bytes =
          EscPosCommandBuilder().text('C', align: PrintAlignment.center).build();
      expect(bytes.sublist(0, 3), [0x1B, 0x61, 0x01]);
    });

    test('right alignment emits ESC a 2', () {
      final bytes =
          EscPosCommandBuilder().text('R', align: PrintAlignment.right).build();
      expect(bytes.sublist(0, 3), [0x1B, 0x61, 0x02]);
    });

    test('newLine emits one 0x0A per line', () {
      final bytes = EscPosCommandBuilder().newLine(3).build();
      expect(bytes, [0x0A, 0x0A, 0x0A]);
    });

    test('feed() emits ESC d n', () {
      final bytes = EscPosCommandBuilder().feed(4).build();
      expect(bytes, [0x1B, 0x64, 4]);
    });

    test('feed() clamps to a single byte (0-255)', () {
      final bytes = EscPosCommandBuilder().feed(999).build();
      expect(bytes, [0x1B, 0x64, 255]);
    });

    test('cut() emits GS V 1 (partial cut)', () {
      final bytes = EscPosCommandBuilder().cut().build();
      expect(bytes, [0x1D, 0x56, 0x01]);
    });

    test('divider() writes the requested number of dashes', () {
      final bytes = EscPosCommandBuilder().divider(width: 8).build();
      // text() with all defaults emits 9 header bytes before the actual
      // text — align (3) + bold-off (3) + doubleHeight-off (3), all
      // unconditional — then divider() appends one newLine() byte after.
      // See the two text()-formatting tests above for why it's 9, not 3.
      const headerBytes = 9;
      final dashBytes = bytes.sublist(headerBytes, headerBytes + 8);
      expect(String.fromCharCodes(dashBytes), '-' * 8);
      expect(bytes[headerBytes + 8], 0x0A); // newLine() after the dashes
      expect(bytes.length, headerBytes + 8 + 1);
    });

    test('testPrint() ends with a cut and is non-empty', () {
      final bytes = EscPosCommandBuilder.testPrint();
      expect(bytes, isNotEmpty);
      expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x01]);
    });

    test('builder calls are chainable and cumulative', () {
      final bytes = EscPosCommandBuilder().init().text('X').cut().build();
      expect(bytes.first, 0x1B); // init's ESC
      expect(bytes.last, 0x01); // cut's final byte
    });
  });
}
