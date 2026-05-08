class TagAndGenres {
  final String id;
  final String name;
  final int? moviesCount;

  TagAndGenres({
    required this.id,
    required this.name,
    this.moviesCount,
  });

  factory TagAndGenres.fromMap(Map<String, dynamic> map, {String? docId}) {
    return TagAndGenres(
      id: docId ?? map['id']?.toString() ?? '',
      name: map['name'] as String? ?? '',
      moviesCount: map['moviesCount'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'moviesCount': moviesCount,
    };
  }
}
