import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 首页快捷入口按钮（人工模式 / 免 root 模式等）。
class HomeEntryButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const HomeEntryButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.18 : 0.06,
                ),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, size: 22.sp, color: color),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
