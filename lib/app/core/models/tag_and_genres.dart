class TagAndGenres {
  final int id;
  final String name;
  final int? moviesCount;

  TagAndGenres({
    required this.id,
    required this.name,
    this.moviesCount,
  });

  factory TagAndGenres.fromMap(Map<String, dynamic> map) {
    return TagAndGenres(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      moviesCount: map['movies_count'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'movies_count': moviesCount,
    };
  }
}
