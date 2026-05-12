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