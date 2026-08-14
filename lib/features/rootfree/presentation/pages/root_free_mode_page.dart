import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/app_info.dart';
import 'package:JsxposedX/core/routes/routes/home_route.dart';
import 'package:JsxposedX/features/home/presentation/widgets/select_app_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 免 root 模式
///
/// 提供一个无需任何激活（无需 root / Xposed / Frida / AI）即可直接使用
/// 所有「免 root 即可实现」功能的入口。所有可用的免 root 能力都聚合在
/// 此页面中，用户点击即可进入对应功能，不做任何权限校验。
class RootFreeModePage extends HookConsumerWidget {
  const RootFreeModePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isZh = context.isZh;

    final features = <_RootFreeFeature>[
      _RootFreeFeature(
        icon: Icons.auto_awesome_motion_rounded,
        color: Colors.pinkAccent,
        title: isZh ? '人工逆向' : 'Manual Reverse',
        subtitle: isZh
            ? '复制提示词到任意外部 AI，粘贴回答自动解析执行，无需激活 AI'
            : 'Copy prompts to any external AI, paste replies to auto-parse & run, no AI activation needed',
        onTap: () {
          SelectAppSheet.show(
            context,
            onSelected: (appInfo) async {
              if (Navigator.canPop(context)) Navigator.pop(context);
              Future.microtask(() {
                if (!context.mounted) return;
                context.push(
                  HomeRoute.toManualAiReverse(packageName: appInfo.packageName),
                );
              });
            },
          );
        },
      ),
      _RootFreeFeature(
        icon: Icons.extension_rounded,
        color: Colors.deepPurpleAccent,
        title: isZh ? '内置模块配置' : 'Bundled Modules',
        subtitle: isZh
            ? '查看、初始化并导出内置 Magisk 模块，无需网络与外部资源'
            : 'Browse, initialize and export bundled Magisk modules offline',
        onTap: () => context.push(HomeRoute.modulesConfig),
      ),
      _RootFreeFeature(
        icon: Icons.code_rounded,
        color: Colors.teal,
        title: isZh ? 'API 手册' : 'API Manual',
        subtitle: isZh
            ? '离线查看 JsxposedX / Frida API 文档与示例'
            : 'Offline JsxposedX / Frida API reference and examples',
        onTap: () => context.push(HomeRoute.apiManual),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? '免 root 模式' : 'Root-free Mode'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              margin: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 4.w),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF38B26D), Color(0xFF2E8B57)],
                ),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_rounded,
                          color: Colors.white, size: 24.sp),
                      SizedBox(width: 8.w),
                      Text(
                        isZh ? '免 root 模式' : 'Root-free Mode',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    isZh
                        ? '无需进行任何激活操作，即可直接使用以下所有免 root 即可实现的功能。'
                        : 'No activation required — use every root-free feature directly.',
                    style: TextStyle(
                      fontSize: 13.sp,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.all(16.w),
                itemCount: features.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, index) {
                  final f = features[index];
                  return _RootFreeFeatureCard(feature: f);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RootFreeFeature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RootFreeFeature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _RootFreeFeatureCard extends StatelessWidget {
  const _RootFreeFeatureCard({super.key, required this.feature});

  final _RootFreeFeature feature;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: feature.onTap,
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: feature.color.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52.w,
                height: 52.w,
                decoration: BoxDecoration(
                  color: feature.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Icon(feature.icon, size: 26.sp, color: feature.color),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      feature.subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        height: 1.4,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
