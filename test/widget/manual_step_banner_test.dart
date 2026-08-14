import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, ManualReverseUiStep step, bool isZh) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualStepBanner(step: step, isZh: isZh),
        ),
      ),
    );
  }

  testWidgets('renders input step label (zh)', (tester) async {
    await pump(tester, ManualReverseUiStep.input, true);
    expect(find.textContaining('输入需求'), findsOneWidget);
  });

  testWidgets('renders promptReady step label', (tester) async {
    await pump(tester, ManualReverseUiStep.promptReady, true);
    expect(find.textContaining('复制提示词'), findsOneWidget);
  });

  testWidgets('renders executing step label', (tester) async {
    await pump(tester, ManualReverseUiStep.executing, false);
    expect(find.textContaining('Executing'), findsOneWidget);
  });

  testWidgets('renders resultReady step label (en)', (tester) async {
    await pump(tester, ManualReverseUiStep.resultReady, false);
    expect(find.textContaining('Step 4'), findsOneWidget);
  });

  testWidgets('banner always renders an icon', (tester) async {
    await pump(tester, ManualReverseUiStep.awaitingAi, true);
    expect(find.byType(Icon), findsWidgets);
  });

  testWidgets('switching steps updates label', (tester) async {
    await pump(tester, ManualReverseUiStep.input, true);
    expect(find.textContaining('输入需求'), findsOneWidget);
    await pump(tester, ManualReverseUiStep.executing, true);
    expect(find.textContaining('执行工具'), findsOneWidget);
  });
}
