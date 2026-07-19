import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../core/widgets/async_view.dart';
import 'pulse/pulse.dart';
import 'bills_page.dart' show inr;

/// Port of ui_kits/member-v2 `ScreensMore.jsx` `LedgerScreen`, now backed by
/// the real `GET /v1/ledger` endpoint (see
/// `apps/mobile-backend/src/modules/ledger/ledger.controller.ts`), which
/// reads the actual `transactions` collection instead of this page deriving
/// approximate debit/credit rows from `/bills` client-side.
class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: AsyncView<List>(
          fetch: () async => (await dio.get('/ledger')).data as List,
          cacheKey: '/ledger',
          builder: (context, entries) {
            final balance = entries.isNotEmpty ? ((entries.first as Map)['balanceAfterTransaction'] as num? ?? 0) : 0;

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PulseTopBar(title: 'My Ledger', subtitle: 'All bill & payment activity', leading: BackButton(color: t.fg2)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: balance > 0 ? t.dangerSoft : t.successSoft, borderRadius: BorderRadius.circular(PulseTokens.radius)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current balance', style: TextStyle(fontSize: 11.5, color: (balance > 0 ? t.danger : t.success).withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(inr(balance), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: balance > 0 ? t.danger : t.success)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.noData, title: 'No ledger entries yet'))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final e = entries[i] as Map;
                        final isCredit = e['type'] == 'Credit';
                        final date = DateTime.tryParse('${e['date']}');
                        final amount = (e['amount'] as num?) ?? 0;
                        return PulseCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e['description'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t.fg1)),
                                    if (date != null)
                                      Text('${date.day}/${date.month}/${date.year}', style: TextStyle(fontSize: 11.5, color: t.fg4)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${isCredit ? '−' : '+'}${inr(amount)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: isCredit ? t.success : t.danger)),
                                  PulsePill(label: isCredit ? 'Credit' : 'Debit', tone: isCredit ? PulseTone.credit : PulseTone.debit, small: true),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
