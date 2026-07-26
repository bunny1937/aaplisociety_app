import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/member/pulse/pulse.dart';

/// The ONE input style for the whole app.
///
/// Audit fix X-1: Rent Payments alone shipped three input languages on a
/// single screen — an outlined pill date picker, a filled text box, and an
/// outlined dropdown with a floating label. Add Tenant added a fourth by
/// using placeholder-as-label (so the label vanished the moment you typed).
///
/// [PulseField] always renders a persistent label above a filled box, plus a
/// reserved error slot so validation never reflows the form.
class PulseField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final TextEditingController? controller;
  final bool required;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter> formatters;
  final int maxLines;
  final String? prefixText;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final String? value;
  final FocusNode? focusNode;

  const PulseField({
    super.key,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.controller,
    this.required = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.formatters = const [],
    this.maxLines = 1,
    this.prefixText,
    this.suffix,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.value,
    this.focusNode,
  });

  /// 10-digit Indian mobile field with the rule enforced, not merely printed
  /// in the placeholder (audit 3.4 flaw 7).
  static PulseField phone({
    required String label,
    required TextEditingController controller,
    String? error,
    bool required = true,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) =>
      PulseField(
        label: label,
        hint: '98XXXXXXXX',
        controller: controller,
        error: error,
        required: required,
        keyboardType: TextInputType.phone,
        textInputAction: textInputAction,
        onChanged: onChanged,
        formatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
      );

  /// Rupee amount field — always shows `₹` as a prefix so no screen has to
  /// write `Amount (Rs)` again (audit X-4).
  static PulseField money({
    required String label,
    required TextEditingController controller,
    String? error,
    String? helper,
    bool required = true,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) =>
      PulseField(
        label: label,
        hint: '0',
        controller: controller,
        error: error,
        helper: helper,
        required: required,
        prefixText: '\u20B9 ',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        onChanged: onChanged,
        formatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final hasError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.fg3,
                ),
              ),
              if (required)
                Text(' *',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.danger)),
              if (!required)
                Text('  Optional',
                    style: TextStyle(fontSize: 11, color: t.fg5)),
            ],
          ),
        ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: formatters,
          maxLines: maxLines,
          minLines: maxLines > 1 ? maxLines : null,
          style: TextStyle(fontSize: 14.5, color: t.fg1),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            prefixStyle: TextStyle(
                fontSize: 14.5, color: t.fg2, fontWeight: FontWeight.w700),
            suffixIcon: suffix,
            filled: true,
            fillColor: enabled ? t.surface : t.surface3,
            hintStyle: TextStyle(fontSize: 14.5, color: t.fg5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                  color: hasError ? t.danger : t.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                  color: hasError ? t.danger : t.brand, width: 1.6),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: t.border, width: 1.5),
            ),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        // Reserved slot: error wins, else helper, else nothing takes up space.
        if (hasError || (helper != null && helper!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(right: 5, top: 1),
                    child: Icon(Icons.error_outline_rounded,
                        size: 13, color: t.danger),
                  ),
                Expanded(
                  child: Text(
                    hasError ? error! : helper!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasError ? t.danger : t.fg4,
                      fontWeight:
                          hasError ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Date field in the SAME filled style as every text field, with a calendar
/// affordance. Replaces the outlined pill buttons on Add Tenant / Rent
/// Payments (audit 3.4 flaw 3, 3.9 flaw 4).
class PulseDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final String? error;
  final String? helper;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String emptyHint;
  final bool enabled;
  const PulseDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.error,
    this.helper,
    this.firstDate,
    this.lastDate,
    this.emptyHint = 'Select a date',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final hasError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.fg3)),
              if (required)
                Text(' *',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.danger)),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: !enabled
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value ?? now,
                    firstDate: firstDate ?? DateTime(now.year - 10),
                    lastDate: lastDate ?? DateTime(now.year + 10),
                  );
                  if (picked != null) onChanged(picked);
                },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: enabled ? t.surface : t.surface3,
              border: Border.all(
                  color: hasError ? t.danger : t.border, width: 1.5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? emptyHint
                        : '${value!.day.toString().padLeft(2, '0')}/'
                            '${value!.month.toString().padLeft(2, '0')}/'
                            '${value!.year}',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: value == null ? t.fg5 : t.fg1,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_rounded, size: 17, color: t.fg4),
              ],
            ),
          ),
        ),
        if (hasError || (helper != null && helper!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              hasError ? error! : helper!,
              style: TextStyle(
                  fontSize: 11.5, color: hasError ? t.danger : t.fg4),
            ),
          ),
      ],
    );
  }
}

/// Month picker for rent periods. Emits `YYYY-MM`, renders `Jul 2026` — the
/// raw period id is never shown (audit 3.9 flaw 6).
class PulseMonthField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool required;
  final String? error;
  final String? helper;
  const PulseMonthField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = true,
    this.error,
    this.helper,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final hasError = error != null && error!.isNotEmpty;
    String pretty = 'Select rent month';
    if (value != null && value!.length >= 7) {
      final y = value!.substring(0, 4);
      final m = int.tryParse(value!.substring(5, 7)) ?? 0;
      if (m >= 1 && m <= 12) pretty = '${_months[m - 1]} $y';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.fg3)),
              if (required)
                Text(' *',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.danger)),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 1, 12),
              initialDatePickerMode: DatePickerMode.year,
              helpText: 'Select rent month',
            );
            if (picked != null) {
              onChanged(
                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
            }
          },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(
                  color: hasError ? t.danger : t.border, width: 1.5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(pretty,
                      style: TextStyle(
                          fontSize: 14.5,
                          color: value == null ? t.fg5 : t.fg1,
                          fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.event_rounded, size: 17, color: t.fg4),
              ],
            ),
          ),
        ),
        if (hasError || (helper != null && helper!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(hasError ? error! : helper!,
                style: TextStyle(
                    fontSize: 11.5, color: hasError ? t.danger : t.fg4)),
          ),
      ],
    );
  }
}
