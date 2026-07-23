import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `SearchInput`.
class PulseSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  const PulseSearchField(
      {super.key, this.controller, this.hint, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: t.fg1),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.fg4),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.fg4),
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: t.border, width: 1.5)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: t.border, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: t.brand, width: 1.5)),
      ),
    );
  }
}
