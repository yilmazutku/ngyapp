class DietRecipe {
  static const String lineField = 'recipes';

  final String url;
  final String? path;
  final String? name;

  const DietRecipe({required this.url, this.path, this.name});

  static DietRecipe? fromMap(Object? raw) {
    if (raw is DietRecipe) return raw;
    if (raw is! Map) return null;
    final Object? url = raw['url'];
    if (url is! String || url.trim().isEmpty) return null;
    final Object? path = raw['path'];
    final Object? name = raw['name'];
    return DietRecipe(
      url: url,
      path: path is String && path.isNotEmpty ? path : null,
      name: name is String && name.isNotEmpty ? name : null,
    );
  }

  static List<DietRecipe?> listFrom(Object? raw) {
    if (raw is! List) return const <DietRecipe?>[];
    return <DietRecipe?>[for (final Object? item in raw) fromMap(item)];
  }

  Map<String, String> toMap() => <String, String>{
        'url': url,
        if (path != null) 'path': path!,
        if (name != null) 'name': name!,
      };
}
