/// Angkas only supports three payment methods. Older records may contain
/// labels such as "GCash" or "Maya"; those are normalised to "E-wallet".
class PaymentMethods {
  PaymentMethods._();

  static const cash = 'Cash';
  static const eWallet = 'E-wallet';
  static const card = 'Card';

  static const all = <String>[cash, eWallet, card];

  static String normalize(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    if (text.isEmpty) return cash;
    if (text.contains('card')) return card;
    if (text.contains('wallet') ||
        text.contains('gcash') ||
        text.contains('maya') ||
        text.contains('credit')) {
      return eWallet;
    }
    if (text.contains('cash')) return cash;
    return cash;
  }
}
