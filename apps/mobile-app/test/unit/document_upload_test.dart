import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/features/tenant/document_upload_field.dart';

void main() {
  group('tenantDocumentFields', () {
    test('has exactly the 4 expected fields with the documented size caps', () {
      final byField = {for (final c in tenantDocumentFields) c.field: c};
      expect(byField.keys.toSet(), {'contract', 'signature', 'aadhaar', 'policeVerification'});
      expect(byField['contract']!.maxBytes, 1048576);
      expect(byField['signature']!.maxBytes, 524288);
      expect(byField['aadhaar']!.maxBytes, 524288);
      expect(byField['policeVerification']!.maxBytes, 524288);
    });
  });

  group('validateDocumentFile', () {
    final contract = tenantDocumentFields.firstWhere((c) => c.field == 'contract');
    final signature = tenantDocumentFields.firstWhere((c) => c.field == 'signature');

    test('accepts a PDF within the contract size cap', () {
      expect(validateDocumentFile(contract, 1000000, 'pdf'), isNull);
    });

    test('rejects a contract PDF over the 1MB cap', () {
      final error = validateDocumentFile(contract, 1048577, 'pdf');
      expect(error, isNotNull);
      expect(error, contains('1MB'));
    });

    test('rejects a non-PDF extension for the contract field', () {
      final error = validateDocumentFile(contract, 1000, 'png');
      expect(error, isNotNull);
      expect(error, contains('PDF'));
    });

    test('accepts a small PNG for the signature field', () {
      expect(validateDocumentFile(signature, 100000, 'png'), isNull);
    });

    test('rejects a signature image over the 512KB cap', () {
      final error = validateDocumentFile(signature, 524289, 'jpg');
      expect(error, isNotNull);
      expect(error, contains('512KB'));
    });

    test('accepts a signature image with no minimum size enforced', () {
      expect(validateDocumentFile(signature, 500, 'jpg'), isNull);
    });
  });
}
