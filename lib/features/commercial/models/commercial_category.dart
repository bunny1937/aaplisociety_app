class CommercialCategory {
  final String id;
  final String name;
  final String slug;
  final String scope; // GLOBAL | SOCIETY
  final bool isActive;

  const CommercialCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.scope,
    this.isActive = true,
  });

  factory CommercialCategory.fromJson(Map json) => CommercialCategory(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        slug: '${json['slug'] ?? ''}',
        scope: '${json['scope'] ?? 'SOCIETY'}',
        isActive: json['isActive'] != false,
      );

  static List<CommercialCategory> listFrom(dynamic raw) =>
      ((raw as List?) ?? const [])
          .map((e) => CommercialCategory.fromJson(Map.from(e as Map)))
          .toList();
}
