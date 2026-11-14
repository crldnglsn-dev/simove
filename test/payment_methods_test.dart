import 'package:flutter_test/flutter_test.dart';
import 'package:simove/core/utils/payment_methods.dart';

void main() {
  group('PaymentMethods', () {
    test('exposes only the three Angkas payment methods', () {
      expect(PaymentMethods.all, ['Cash', 'E-wallet', 'Card']);
    });

    test('normalises wallet brands', () {
      expect(PaymentMethods.normalize('GCash'), 'E-wallet');
      expect(PaymentMethods.normalize('Maya'), 'E-wallet');
      expect(PaymentMethods.normalize('Angkas Credit'), 'E-wallet');
      expect(PaymentMethods.normalize('e-wallet'), 'E-wallet');
    });

    test('normalises cards', () {
      expect(PaymentMethods.normalize('Card'), 'Card');
      expect(PaymentMethods.normalize('Credit Card'), 'Card');
      expect(PaymentMethods.normalize('Debit Card'), 'Card');
    });

    test('defaults unknown or empty values to Cash', () {
      expect(PaymentMethods.normalize(null), 'Cash');
      expect(PaymentMethods.normalize(''), 'Cash');
      expect(PaymentMethods.normalize('Cash'), 'Cash');
    });
  });
}
