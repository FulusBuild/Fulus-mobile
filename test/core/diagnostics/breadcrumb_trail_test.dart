import 'package:fulus_mobile/core/diagnostics/breadcrumbs/breadcrumb_trail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BreadcrumbTrail', () {
    test('records breadcrumbs in order', () {
      final trail = BreadcrumbTrail();
      trail.add('First');
      trail.add('Second');
      trail.add('Third');

      final snapshot = trail.snapshot();
      expect(snapshot.map((b) => b.message).toList(), ['First', 'Second', 'Third']);
    });

    test('is bounded — oldest entries drop once maxEntries is exceeded', () {
      final trail = BreadcrumbTrail(maxEntries: 3);
      trail.add('One');
      trail.add('Two');
      trail.add('Three');
      trail.add('Four');

      expect(trail.length, 3);
      final snapshot = trail.snapshot();
      expect(snapshot.map((b) => b.message).toList(), ['Two', 'Three', 'Four']);
    });

    test('snapshot(limit:) returns only the most recent N, oldest-first', () {
      final trail = BreadcrumbTrail();
      for (var i = 1; i <= 10; i++) {
        trail.add('Event $i');
      }
      final snapshot = trail.snapshot(limit: 3);
      expect(snapshot.map((b) => b.message).toList(), ['Event 8', 'Event 9', 'Event 10']);
    });

    test('snapshot does not remove entries — a later, closely-following '
        'failure still has full context', () {
      final trail = BreadcrumbTrail();
      trail.add('First');
      trail.add('Second');

      trail.snapshot(); // simulates one event being captured
      trail.add('Third');

      final secondSnapshot = trail.snapshot();
      expect(secondSnapshot.map((b) => b.message).toList(), ['First', 'Second', 'Third']);
    });

    test('carries through category and data', () {
      final trail = BreadcrumbTrail();
      trail.add('Product added to cart', category: 'sales', data: {'Product ID': '184'});

      final crumb = trail.snapshot().single;
      expect(crumb.category, 'sales');
      expect(crumb.data['Product ID'], '184');
    });

    test('clear empties the trail', () {
      final trail = BreadcrumbTrail();
      trail.add('One');
      trail.clear();
      expect(trail.length, 0);
      expect(trail.snapshot(), isEmpty);
    });
  });
}
