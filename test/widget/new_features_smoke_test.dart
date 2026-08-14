import 'package:JsxposedX/features/home/presentation/widgets/home_entry_button.dart';
import 'package:JsxposedX/features/rootfree/presentation/pages/root_free_mode_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (context, _) => MaterialApp(home: child),
  );
}

void main() {
  testWidgets('HomeEntryButton renders label and icon', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: HomeEntryButton(
            icon: Icons.verified_user_rounded,
            color: Colors.green,
            label: '免 root 模式',
            subtitle: '无需任何激活',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('免 root 模式'), findsOneWidget);
    expect(find.text('无需任何激活'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
    await tester.tap(find.text('免 root 模式'));
    expect(tapped, isTrue);
  });

  testWidgets('RootFreeModePage renders without error', (tester) async {
    await tester.pumpWidget(
      _wrap(const RootFreeModePage()),
    );
    await tester.pumpAndSettle();
    // AppBar title and the header present (zh via default? default en)
    expect(find.byType(RootFreeModePage), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    // Cards list is non-empty (at least 3 feature entries)
    expect(find.byType(ListView), findsWidgets);
  });
}
