---
Task ID: 1
Agent: Main
Task: All 5 tasks for CM Movies v1.10.0

Work Log:
- Task 5 (Dark Mode Theme): Changed kDarkBg from Color(0xFF0A0A0A) to Color(0xFF121212), updated all hardcoded references in movie_detail_screen.dart, series_detail_screen.dart, tmdb_generator_page.dart, and main.dart
- Task 1 (UI Cleaning Fix): Added clean "Details" section to Detail Tab in both Movie and Series detail screens. Movies show Quality, Format, Genre, Duration, Director. Series show Seasons, Episodes, Genre only. No background boxes/borders, clean text rows only. Added format and fileSize fields to MovieDetail model.
- Task 2 (Cast Page & Loading): Created ActorMoviesScreen that shows only Firestore movies for a given actor (no TMDB API calls). Added getMoviesByActor() method to FirestoreContentService. Added GestureDetector to cast items in both detail screens for tap navigation.
- Task 3 (Infinite Scroll Fix): Added Set<String> _seenIds to CategoryPage, MoviesPage, SeriesPage for deduplication. Modified _loadMore() to check for duplicate IDs before adding. Added extra condition: _hasMore = result['hasMore'] && incoming.isNotEmpty.
- Task 4 (TabBarView Height Fix): Removed MediaQuery.removePadding from movie_detail_screen.dart. Added ClampingScrollPhysics to all tab ListViews (Detail, Download, Explore tabs).

Stage Summary:
- Version bumped to v1.10.0
- 11 files changed, 506 insertions, 25 deletions
- New file: actor_movies_screen.dart
- Pushed to GitHub: https://github.com/ttg92195-cmyk/CM-APP (branch: main)
