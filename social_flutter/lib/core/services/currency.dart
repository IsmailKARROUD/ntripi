class Currency {
  final String code;
  final String name;
  final String type;

  Currency({
    required this.code,
    required this.name,
    required this.type,
  });

  factory Currency.fromJson(Map<String, dynamic> json) {
    return Currency(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

/// Maps an ISO currency code to its display symbol; falls back to the raw
/// code for anything not in the map (the app serves many currencies).
String currencySymbol(String code) {
  const symbols = {
    'EUR': '€',
    'USD': '\$',
    'GBP': '£',
    'JPY': '¥',
    'CHF': 'CHF',
    'MAD': 'DH',
  };
  return symbols[code.toUpperCase()] ?? code;
}

/// Formats a money amount as "20,00 €" — 2 decimals, comma decimal
/// separator, currency symbol suffix. Callers decide the free/unset cases.
String formatMoney(double amount, String currency) =>
    '${amount.toStringAsFixed(2).replaceAll('.', ',')} ${currencySymbol(currency)}';