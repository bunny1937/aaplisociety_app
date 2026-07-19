import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';
import '../../core/widgets/async_view.dart';
import 'pulse/pulse.dart';
import 'pulse/bill_pdf.dart';
import 'bills_page.dart' show inr;

/// Port of ui_kits/member-v2 `ScreensMore.jsx` `ReceiptsScreen`, now backed
/// by the real `GET /v1/receipts` endpoint (see
/// `apps/mobile-backend/src/modules/receipts/receipt.controller.ts`), which
/// reads the actual `receipts` collection instead of this page deriving one
/// fake receipt per paid bill client-side. "Download" produces a real PDF
/// via `renderReceiptPdf`.
class ReceiptsPage extends StatelessWidget {
  const ReceiptsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: AsyncView<List>(
          fetch: () async => (await dio.get('/receipts')).data as List,
          cacheKey: '/receipts',
          builder: (context, receipts) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PulseTopBar(title: 'Receipts', subtitle: 'Payment receipts for your flat', leading: BackButton(color: t.fg2)),
                ),
                if (receipts.isEmpty)
                  const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.noData, title: 'No receipts yet'))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: receipts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = receipts[i] as Map;
                        final amount = (r['amount'] as num?) ?? 0;
                        final receiptNo = '${r['receiptNo'] ?? '—'}';
                        final periodLabel = '${r['periodLabel'] ?? ''}';
                        final date = DateTime.tryParse('${r['paidAt']}');
                        return PulseCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(11)),
                                child: Icon(Icons.receipt_long_rounded, color: t.brand, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(receiptNo, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.fg1)),
                                    Text(
                                      '$periodLabel${date != null ? ' · ${date.day}/${date.month}/${date.year}' : ''}',
                                      style: TextStyle(fontSize: 11.5, color: t.fg4),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(inr(amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.fg1)),
                                  GestureDetector(
                                    onTap: () async {
                                      final bytes = await renderReceiptPdf(r, periodLabel: periodLabel, formatInr: inr);
                                      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$receiptNo.pdf');
                                    },
                                    child: Text('Download', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.brand)),
                                  ),
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
