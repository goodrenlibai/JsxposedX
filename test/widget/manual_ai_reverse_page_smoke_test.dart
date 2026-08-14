import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke tests for the redesigned manual reverse page widgets. The full page
/// requires a native APK analysis environment, so here we assert the shared
/// building blocks render without error and that the step banner is present.
void main() {
  Widget wrap(Widget child) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: child),
    );
  }

  testWidgets('step banner renders for each step', (tester) async {
    for (final step in ManualReverseUiStep.values) {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: ManualStepBanner(step: step, isZh: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ManualStepBanner), findsOneWidget);
      expect(find.byType(Icon), findsWidgets);
    }
  });
}
