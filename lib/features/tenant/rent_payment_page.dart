import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/pulse_field.dart';
import '../../core/widgets/pulse_scaffold.dart';
import '../member/pulse/pulse.dart';
import 'tenant_api.dart';
import 'tenant_ui.dart';

const List<String> kPaymentModes = [
  'Cash',
  'UPI',
  'BankTransfer',
  'Cheque',
  'Online',
];

/// Human labels — the API values are camel-case, but users should never see
/// `BankTransfer` on screen (audit 3.9 flaw 5).
const Map<String, String> kPaymentModeLabels = {
  'Cash': 'Cash',
  'UPI': 'UPI',
  'BankTransfer': 'Bank transfer',
  'Cheque': 'Cheque',
  'Online': 'Online',
};

/// Ported from the mockup `ScreensRentPayments.jsx > RentPaymentsScreen`:
/// a confirmed-total hero, a record form, then filterable history.
class RentPaymentPage extends StatefulWidget {
  const RentPaymentPage({super.key});
  @override
  State<RentPaymentPage> createState() => _RentPaymentPageState();
}

class _RentPaymentPageState extends State<RentPaymentPage> {
  final _viewKey = GlobalKey<AsyncViewState<List>>();
  final _amount = TextEditingController();
  String? _month;
  String _mode = 'UPI';
  String _filter = 'all';
  final Map<String, String?> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final e = <String, String?>{};
    if (_month == null || _month!.isEmpty) {
      e['month'] = 'Select the rent month';
    }
    final amt = num.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) e['amount'] = 'Enter a valid amount';
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    if (e.isNotEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await recordRentPayment(context.read<Dio>(), {
        'month': _month,
        'amount': amt,
        'paymentMode': _mode,
      });
      if (!mounted) return;
      showAppToast(context, 'Rent payment recorded',
          kind: AppToastKind.success);
      _amount.clear();
      setState(() => _month = null);
      await _viewKey.currentState?.reload();
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseScaffold(
      title: 'Rent Payments',
      subtitle: 'Record and track rent from your tenant',
      child: AsyncView<List>(
        key: _viewKey,
        fetch: () => fetchRentPayments(context.read<Dio>()),
        builder: (context, raw) {
          final rents = raw.cast<Map>();
          final confirmed = rents.where((r) =>
              r['status']?.toString().toLowerCase() == 'confirmed' ||
              r['status']?.toString().toLowerCase() == 'approved');
          final totalConfirmed = confirmed.fold<num>(
              0, (sum, r) => sum + ((r['amount'] as num?) ?? 0));
          final filtered = switch (_filter) {
            'confirmed' => rents
                .where((r) => ['confirmed', 'approved']
                    .contains(r['status']?.toString().toLowerCase()))
                .toList(),
            'pending' => rents
                .where((r) =>
                    r['status']?.toString().toLowerCase() == 'pending')
                .toList(),
            'rejected' => rents
                .where((r) =>
                    r['status']?.toString().toLowerCase() == 'rejected')
                .toList(),
            _ => rents,
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              // ---- Confirmed total hero -----------------------------------
              PulseCard(
                padding: const EdgeInsets.all(16),
                color: t.successSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL CONFIRMED',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: t.success)),
                    const SizedBox(height: 4),
                    Text(
                      inr(totalConfirmed),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: t.success,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ---- Record a payment ---------------------------------------
              const TenantSectionTitle('Record a payment'),
              PulseCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PulseMonthField(
                      label: 'Rent month',
                      value: _month,
                      required: true,
                      error: _errors['month'],
                      onChanged: (v) => setState(() => _month = v),
                    ),
                    const SizedBox(height: 12),
                    PulseField.money(
                        label: 'Amount',
                        controller: _amount,
                        error: _errors['amount']),
                    const SizedBox(height: 12),
                    Text('Payment mode',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.fg3)),
                    const SizedBox(height: 6),
                    // Chips rather than a dropdown: five short options are
                    // faster to hit and always visible.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kPaymentModes
                          .map((m) => _ModeChip(
                                label: kPaymentModeLabels[m] ?? m,
                                selected: _mode == m,
                                onTap: () => setState(() => _mode = m),
                              ))
                          .toList(),
                    ),
                    if (_mode == 'Online') ...[
                      const SizedBox(height: 12),
                      const TenantBanner(
                        'Online payments are recorded manually for now \u2014 '
                        'gateway integration is coming later.',
                        neutral: true,
                        icon: Icons.info_outline_rounded,
                      ),
                    ],
                    const SizedBox(height: 16),
                    PulseButton(
                      label: 'Record payment',
                      full: true,
                      loading: _saving,
                      onTap: _record,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ---- History ------------------------------------------------
              const TenantSectionTitle('History'),
              PulseSegmented<String>(
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                small: true,
                options: [
                  PulseSegmentedOption(
                      value: 'all', label: 'All', count: rents.length),
                  const PulseSegmentedOption(
                      value: 'confirmed', label: 'Confirmed'),
                  const PulseSegmentedOption(
                      value: 'pending', label: 'Pending'),
                  const PulseSegmentedOption(
                      value: 'rejected', label: 'Rejected'),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const PulseEmptyState(
                  illo: PulseIllo.noData,
                  title: 'No payments',
                  subtitle: 'No rent payments match this filter yet.',
                )
              else
                // Month grouping so a long history stays scannable
                // (audit 3.9 flaw 3).
                ...groupByMonth<Map>(
                  filtered,
                  (r) => parseDate(r['paidAt'] ?? r['createdAt']),
                ).entries.expand(
                  (group) => [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                        group.key,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: t.fg4),
                      ),
                    ),
                    ...group.value.map((r) => RentTile(rent: r)),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          // 44px min height keeps every chip a legal touch target.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.brand : t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? t.brand : t.border, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 15, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : t.fg2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
