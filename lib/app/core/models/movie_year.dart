class MovieYear {
  final String? year;
  final int? moviesCount;

  MovieYear({
    this.year,
    this.moviesCount,
  });

  factory MovieYear.fromMap(Map<String, dynamic> map) {
    return MovieYear(
      year: map['year']?.toString(),
      moviesCount: map['movies_count'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'year': year,
      'movies_count': moviesCount,
    };
  }
}
