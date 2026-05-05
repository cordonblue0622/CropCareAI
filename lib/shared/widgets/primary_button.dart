import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? trailingIcon;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.trailingIcon,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: foregroundColor ?? Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          disabledBackgroundColor: bg.withValues(alpha: 0.6),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    trailingIcon!,
                  ],
                ],
              ),
      ),
    );
  }
}
