import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final _inrFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2);
// pw's built-in fonts have no ₹ glyph (renders as a blank box), so PDFs use
// "Rs." instead of the ₹ symbol used elsewhere in the app's own UI.
String _inr(num n) => _inrFormat.format(n.abs());

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Builds a bill PDF natively via `pw.Widget` layout, from the same fields
/// `bill_format_sheet.dart` already renders on-screen. Replaces a prior
/// version built on `Printing.convertHtml` (HTML→PDF via a hidden platform
/// WebView) — deprecated, and unreliable in practice (silently produced
/// empty/broken output on several test devices), which is what made
/// Save/Share on bills not actually work.
Future<Uint8List> renderBillPdf(Map bill, {String? societyName}) async {
  final amount = (bill['amount'] as num?) ?? 0;
  final paid = (bill['amountPaid'] as num?) ?? 0;
  final prevBalance = (bill['previousBalance'] as num?) ?? 0;
  final due = DateTime.tryParse('${bill['dueDate']}');
  final charges = (bill['charges'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final period = '${bill['periodLabel'] ?? bill['title'] ?? bill['period'] ?? 'Bill'}';
  final wing = bill['wing']?.toString();
  final flatNo = bill['flatNo']?.toString();
  final flatLabel = (flatNo == null || flatNo.isEmpty) ? '-' : (wing != null && wing.isNotEmpty ? '$wing-$flatNo' : flatNo);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text((societyName ?? 'Your Society').toUpperCase(), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text('MAINTENANCE BILL', style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (due != null) pw.Text('Due ${due.day} ${_months[due.month - 1]} ${due.year}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Period: $period', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Flat: $flatLabel', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Owner: ${bill['ownerName'] ?? '-'}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Area: ${bill['areaSqft'] != null ? '${bill['areaSqft']} sqft' : '-'}', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.Divider(height: 24),
          if (charges.isNotEmpty) ...[
            pw.Table(
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text('Charge', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text('Amount', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ]),
                ...charges.entries.map((e) => pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(e.key)),
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(_inr((e.value as num?) ?? 0), textAlign: pw.TextAlign.right)),
                    ])),
                if (prevBalance > 0)
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text('Previous balance carried forward')),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(_inr(prevBalance), textAlign: pw.TextAlign.right)),
                  ]),
              ],
            ),
            pw.Divider(height: 16),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text(_inr(amount), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Payable', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text(_inr(amount - paid), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(child: pw.Text('Computer generated bill - no signature required', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
        ],
      ),
    ),
  );
  return doc.save();
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
          pw.Text('PAYMENT RECEIPT', style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Receipt No: ${receipt['receiptNo'] ?? '—'}'),
          pw.Text('Period: $periodLabel'),
          pw.Text('Payment mode: ${receipt['paymentMode'] ?? '—'}'),
          if (receipt['transactionId'] != null) pw.Text('Transaction ID: ${receipt['transactionId']}'),
          pw.Divider(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Amount paid', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(formatInr(amount), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
