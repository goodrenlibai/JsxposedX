import 'package:JsxposedX/features/ai/manual/presentation/pages/manual_qa_page.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_copy_card.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      const MaterialApp(
        home: ManualQaPage(title: 'API Assistant', systemPrompt: 'You are an API assistant.'),
      ),
    );
  }

  testWidgets('renders request input and generate button', (tester) async {
    await pump(tester);
    expect(find.text('API Assistant · Manual'), findsOneWidget);
    expect(find.text('Generate prompt'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('generating a prompt shows a copy card', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Enter your question'),
      'Analyze login',
    );
    await tester.tap(find.text('Generate prompt'));
    await tester.pumpAndSettle();

    expect(find.byType(ManualCopyCard), findsOneWidget);
    expect(find.textContaining('Analyze login'), findsWidgets);
    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('step banner reflects the initial step', (tester) async {
    await pump(tester);
    expect(find.byType(ManualStepBanner), findsOneWidget);
    expect(find.textContaining('Step 1'), findsOneWidget);
  });

  testWidgets('empty request does not create a prompt card', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Enter your question'),
      '   ',
    );
    await tester.tap(find.text('Generate prompt'));
    await tester.pump();
    // Guard returns early; no copy card appears.
    expect(find.byType(ManualCopyCard), findsNothing);
  });
}
