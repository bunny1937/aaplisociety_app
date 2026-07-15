import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Converts a bill's server-rendered `billHtml` (see
/// `apps/mobile-backend/src/modules/bills/bill.controller.ts`
/// `buildFallbackBillHtml` — every bill from `GET /bills` is guaranteed to
/// have non-empty `billHtml`) into real PDF bytes for Save/Share, replacing
/// the toast-only placeholders `bill_detail_sheet.dart`/
/// `bill_format_sheet.dart` used before.
Future<Uint8List> renderBillPdf(Map bill) async {
  final html = '${bill['billHtml'] ?? ''}';
  final fallback = '<div style="font-family:Arial;padding:24px;">No bill content available.</div>';
  return Printing.convertHtml(format: PdfPageFormat.a4, html: html.isNotEmpty ? html : fallback);
}

/// Builds a minimal printable receipt PDF client-side. Real `Receipt`
/// documents (see `GET /v1/receipts`) don't carry rendered HTML like bills
/// do, so this constructs a small `pw.Document` directly instead of going
/// through `Printing.convertHtml`.
Future<Uint8List> renderReceiptPdf(
  Map receipt, {
  required String periodLabel,
  required String Function(num) formatInr,
}) async {
  final doc = pw.Document();
  final amount = (receipt['amount'] as num?) ?? 0;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Receipt No: ${receipt['receiptNo'] ?? '—'}'),
          pw.Text('Period: $periodLabel'),
          pw.Text('Payment mode: ${receipt['paymentMode'] ?? '—'}'),
          if (receipt['transactionId'] != null) pw.Text('Transaction ID: ${receipt['transactionId']}'),
          pw.Divider(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Amount paid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(formatInr(amount), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
