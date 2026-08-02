import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/pulse_scaffold.dart';
import 'pulse/pulse.dart';

/// **Essential contacts / services directory.**
///
/// The one screen that was asked for and never built: the numbers a resident
/// actually needs at 11pm — ambulance, fire, the society office, the plumber,
/// the gas agency. Reachable from BOTH the owner profile and the tenant
/// profile, because a tenant needs a plumber exactly as much as an owner does.
///
/// The national/state helplines are compiled in so the page is useful with no
/// backend and no signal-dependent fetch. Society-specific numbers are layered
/// on top from `GET /society/contacts` when that endpoint answers; a failure
/// there is silent and simply leaves the built-in directory showing.
class EssentialContactsPage extends StatefulWidget {
  const EssentialContactsPage({super.key});
  @override
  State<EssentialContactsPage> createState() => _EssentialContactsPageState();
}

class _Contact {
  const _Contact(this.name, this.number, {this.note, this.urgent = false});
  final String name;
  final String number;
  final String? note;
  final bool urgent;
}

class _Group {
  const _Group(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<_Contact> items;
}

class _EssentialContactsPageState extends State<EssentialContactsPage> {
  List<_Contact> _society = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSocietyContacts();
  }

  /// Best-effort. The built-in directory is the product; this is a bonus.
  Future<void> _loadSocietyContacts() async {
    try {
      final res = await context.read<Dio>().get('/society/contacts');
      final raw = (res.data as Map)['contacts'];
      if (raw is! List) return;
      final parsed = raw
          .whereType<Map>()
          .map((c) => _Contact(
                '${c['name'] ?? c['label'] ?? 'Contact'}',
                '${c['phone'] ?? c['number'] ?? ''}',
                note: c['role']?.toString() ?? c['note']?.toString(),
              ))
          .where((c) => c.number.trim().isNotEmpty)
          .toList();
      if (!mounted || parsed.isEmpty) return;
      setState(() => _society = parsed);
    } catch (_) {
      // Endpoint not deployed / offline / not permitted. Stay quiet.
    }
  }

  static const _emergency = <_Contact>[
    _Contact('All-in-one emergency', '112',
        note: 'Police, fire and ambulance', urgent: true),
    _Contact('Police', '100', urgent: true),
    _Contact('Fire brigade', '101', urgent: true),
    _Contact('Ambulance', '102', urgent: true),
    _Contact('Emergency ambulance', '108',
        note: 'Medical emergency response', urgent: true),
  ];

  static const _helplines = <_Contact>[
    _Contact('Women\u2019s helpline', '1091'),
    _Contact('Child helpline', '1098'),
    _Contact('Senior citizen helpline', '14567'),
    _Contact('Cyber crime / online fraud', '1930'),
    _Contact('Mental health (Tele-MANAS)', '14416'),
    _Contact('Blood bank information', '104'),
    _Contact('Anti-poison', '1066'),
    _Contact('Railway helpline', '139'),
    _Contact('Road accident emergency', '1073'),
    _Contact('Disaster management', '1078'),
  ];

  static const _utilities = <_Contact>[
    _Contact('Electricity breakdown (MSEDCL)', '1912'),
    _Contact('Electricity toll free', '18002333435'),
    _Contact('LPG gas leak emergency', '1906'),
    _Contact('Water supply complaint', '1916'),
    _Contact('Municipal helpline', '1800221293'),
    _Contact('Gas agency booking (IOCL)', '7718955555'),
  ];

  List<_Group> get _groups => [
        _Group('Emergency', Icons.emergency_share_rounded, _emergency),
        if (_society.isNotEmpty)
          _Group('Society', Icons.apartment_rounded, _society),
        _Group('Helplines', Icons.support_agent_rounded, _helplines),
        _Group('Utilities', Icons.bolt_rounded, _utilities),
      ];

  Future<void> _call(String number) async {
    Haptics.light();
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$digits');
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      showAppToast(context, 'Could not open the dialer',
          kind: AppToastKind.alert);
    }
  }

  bool _matches(_Contact c) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    return c.name.toLowerCase().contains(q) ||
        c.number.contains(q) ||
        (c.note ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final groups = _groups
        .map((g) => _Group(g.title, g.icon, g.items.where(_matches).toList()))
        .where((g) => g.items.isNotEmpty)
        .toList();

    return PulseScaffold(
      title: 'Essential contacts',
      subtitle: 'Emergency, society and utility numbers',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          PulseSearchField(
            hint: 'Search a service or number',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 6),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text('No contact matches “$_query”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: t.fg4)),
            ),
          for (final g in groups) ...[
            PulseSectionLabel(g.title),
            PulseGroup(
              children: [
                for (final c in g.items)
                  PulseRow(
                    icon: c.urgent ? Icons.priority_high_rounded : g.icon,
                    label: c.name,
                    sublabel: [c.number, if (c.note != null) c.note!]
                        .join('  \u00B7  '),
                    danger: c.urgent,
                    trailing: Icon(Icons.call_rounded,
                        size: 18, color: c.urgent ? t.danger : t.brand),
                    onTap: () => _call(c.number),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Tap any row to dial. Emergency numbers are toll-free and work '
            'even without balance.',
            style: TextStyle(fontSize: 11.5, color: t.fg5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
