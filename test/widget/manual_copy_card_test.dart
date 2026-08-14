import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_copy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows title and body text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManualCopyCard(
            title: 'Copy this',
            body: 'payload text',
            onCopy: _noop,
            accent: Colors.teal,
          ),
        ),
      ),
    );
    expect(find.text('Copy this'), findsOneWidget);
    expect(find.text('payload text'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('tapping copy invokes callback', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualCopyCard(
            title: 'T',
            body: 'B',
            onCopy: () => copied = true,
            accent: Colors.teal,
          ),
        ),
      ),
    );
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(copied, isTrue);
  });

  testWidgets('non-selectable mode renders plain text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManualCopyCard(
            title: 'T',
            body: 'plain',
            onCopy: _noop,
            accent: Colors.teal,
            selectable: false,
          ),
        ),
      ),
    );
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('plain'), findsOneWidget);
  });
}

void _noop() {}
