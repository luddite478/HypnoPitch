import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ActionButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color border;
  final Color textColor;
  final VoidCallback? onTap;
  final double height;
  final EdgeInsets padding;
  final double fontSize;

  const ActionButton({
    super.key,
    required this.label,
    required this.background,
    required this.border,
    required this.textColor,
    this.onTap,
    this.height = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: padding,
          backgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: border, width: 1.0),
          ),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
