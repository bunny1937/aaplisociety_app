import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../auth/bloc/auth_bloc.dart';
import '../member/pulse/pulse.dart';
import 'gate_tab.dart';
import 'log_tab.dart';
import 'new_entry_tab.dart';
import 'verify_tab.dart';

class SecurityShell extends StatefulWidget {
  const SecurityShell({super.key});
  @override
  State<SecurityShell> createState() => _SecurityShellState();
}

class _SecurityShellState extends State<SecurityShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text('AapliSocietyy · Guard App', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.fg3)),
        actions: [
          PulseIconButton(
            icon: Icons.logout_rounded,
            onTap: () { Haptics.heavy(); context.read<AuthBloc>().add(LogoutRequested()); context.go('/login'); },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [GateTab(), NewEntryTab(), VerifyTab(), LogTab()],
        ),
      ),
      bottomNavigationBar: _GuardNavBar(
        current: _tab,
        onSelect: (i) { Haptics.light(); setState(() => _tab = i); },
      ),
    );
  }
}

class _GuardNavBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const _GuardNavBar({required this.current, required this.onSelect});

  static const _items = <(IconData, String)>[
    (Icons.grid_view_rounded, 'Gate'),
    (Icons.person_add_alt_1_rounded, 'New Entry'),
    (Icons.qr_code_scanner_rounded, 'Verify'),
    (Icons.receipt_long_rounded, 'Log'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border, width: 1))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final (icon, label) = _items[i];
              final active = i == current;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 22, color: active ? t.brand : t.fg4),
                      const SizedBox(height: 3),
                      Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? t.brand : t.fg4)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
