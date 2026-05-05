import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool isPassword;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final void Function(String)? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.isPassword = false,
    this.controller,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textGray,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: widget.isPassword && _obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onChanged: widget.onChanged,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          style: const TextStyle(fontSize: 15, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle:
                const TextStyle(color: AppColors.textLightGray, fontSize: 15),
            prefixIcon: widget.prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: widget.prefixIcon,
                  )
                : null,
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: widget.suffixIcon ??
                (widget.isPassword
                    ? IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textLightGray,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null),
          ),
        ),
      ],
    );
  }
}
