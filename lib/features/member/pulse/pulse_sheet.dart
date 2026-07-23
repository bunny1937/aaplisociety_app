import 'package:flutter/material.dart';
import '../../../core/theme/haptics.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `Sheet` — bottom sheet with drag handle and
/// optional title+close row. Wraps `showModalBottomSheet`; call
/// [showPulseSheet] rather than instantiating this directly.
Future<T?> showPulseSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool full = false,
  bool isDismissible = true,
}) {
  final t = context.pulse;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x73000A19),
    builder: (ctx) => _PulseSheetChrome(
        title: title, full: full, tokens: t, child: builder(ctx)),
  );
}

class _PulseSheetChrome extends StatelessWidget {
  final String? title;
  final bool full;
  final PulseTokens tokens;
  final Widget child;
  const _PulseSheetChrome(
      {required this.title,
      required this.full,
      required this.tokens,
      required this.child});
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * (full ? 0.94 : 0.88);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PulseTokens.radiusLg)),
            boxShadow: tokens.shadowPop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                child: Container(
                    width: 36,
                    height: 4.5,
                    decoration: BoxDecoration(
                        color: tokens.border,
                        borderRadius: BorderRadius.circular(999))),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title!,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: tokens.fg1,
                                letterSpacing: -0.3)),
                      ),
                      GestureDetector(
                        onTap: () {
                          Haptics.light();
                          Navigator.of(context).maybePop();
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: tokens.surface3, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: tokens.fg3),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
