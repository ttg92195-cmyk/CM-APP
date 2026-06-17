import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/services/search_history_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SearchHistoryService _historyService = SearchHistoryService.instance;
  Timer? _debounceTimer;

  List<Movie> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  // Local-only search history (no Firestore usage — stored in SharedPreferences).
  List<String> _searchHistory = [];
  StreamSubscription<List<String>>? _historySub;

  // Pagination state for infinite scroll
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Set<String> _seenIds = {};

  // Filter state
  String? _selectedGenre;
  String? _selectedType; // 'movie' or 'series'
  String? _selectedYear;
  String? _selectedRating; // minimum rating
  String _sortBy = 'latest'; // 'latest', 'rating', 'name'

  // Available filter options
  List<TagAndGenres> _genres = [];
  List<String> _years = [];
  bool _isLoadingFilters = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load local search history (no Firestore cost).
    _historyService.load().then((h) {
      if (mounted) setState(() => _searchHistory = h);
    });
    // Keep UI in sync if history changes elsewhere (e.g. add/remove/clear).
    _historySub = _historyService.changes.listen((h) {
      if (mounted) setState(() => _searchHistory = h);
    });
    _searchController.addListener(() {
      setState(() {}); // Rebuild to show/hide clear button + history panel
      // Debounced auto-search: wait 400ms after user stops typing
      _debounceTimer?.cancel();
      final query = _searchController.text.trim();
      if (query.isNotEmpty || _hasActiveFilters) {
        _debounceTimer = Timer(const Duration(milliseconds: 400), () {
          _search();
        });
      } else if (query.isEmpty && !_hasActiveFilters) {
        setState(() {
          _results = [];
          _hasSearched = false;
        });
      }
    });
    _loadFilterOptions();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _historySub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final results = await Future.wait([
        _contentService.getGenres(),
        _contentService.getAvailableYears(),
      ]);
      if (mounted) {
        setState(() {
          _genres = results[0] as List<TagAndGenres>;
          _years = results[1] as List<String>;
          _isLoadingFilters = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading filter options: $e');
      if (mounted) {
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  bool get _hasActiveFilters =>
      _selectedGenre != null ||
      _selectedType != null ||
      _selectedYear != null ||
      _selectedRating != null ||
      _sortBy != 'latest';

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty && !_hasActiveFilters) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    // Save non-empty queries to local search history (no Firestore cost).
    if (query.isNotEmpty) {
      await _historyService.add(query);
    }

    // Reset pagination state for new search
    _lastDoc = null;
    _hasMore = true;
    _seenIds.clear();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final result = await _contentService.searchMoviesWithFilters(
        keyword: query.isEmpty ? null : query,
        genre: _selectedGenre,
        type: _selectedType,
        year: _selectedYear,
        rating: _selectedRating,
        sortBy: _sortBy,
        limit: 50,
      );
      if (mounted) {
        final movies = result['movies'] as List<Movie>;
        // Track IDs to prevent duplicates
        for (final m in movies) {
          _seenIds.add(m.id);
        }
        setState(() {
          _results = movies;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _hasMore = (result['hasMore'] as bool? ?? false) && movies.length >= 20;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedGenre = null;
      _selectedType = null;
      _selectedYear = null;
      _selectedRating = null;
      _sortBy = 'latest';
      _lastDoc = null;
      _hasMore = true;
      _seenIds.clear();
    });
    if (_searchController.text.isNotEmpty || _hasSearched) {
      _search();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);
    try {
      final query = _searchController.text.trim();
      final result = await _contentService.searchMoviesWithFilters(
        keyword: query.isEmpty ? null : query,
        genre: _selectedGenre,
        type: _selectedType,
        year: _selectedYear,
        rating: _selectedRating,
        sortBy: _sortBy,
        limit: 50,
        startAfter: _lastDoc,
      );
      if (mounted) {
        final newMovies = result['movies'] as List<Movie>;
        // Deduplicate by ID
        final dedupedMovies = <Movie>[];
        for (final m in newMovies) {
          if (!_seenIds.contains(m.id)) {
            _seenIds.add(m.id);
            dedupedMovies.add(m);
          }
        }
        setState(() {
          _results.addAll(dedupedMovies);
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _hasMore = (result['hasMore'] as bool? ?? false) && newMovies.isNotEmpty;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Load more error: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _removeFilter(String filterType) {
    setState(() {
      switch (filterType) {
        case 'genre':
          _selectedGenre = null;
          break;
        case 'type':
          _selectedType = null;
          break;
        case 'year':
          _selectedYear = null;
          break;
        case 'rating':
          _selectedRating = null;
          break;
      }
    });
    _search();
  }

  void _navigateToDetail(Movie movie) {
    final isSeries = movie.type == 'series';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isSeries
            ? SeriesDetailScreen(slug: movie.slug)
            : MovieDetailScreen(slug: movie.slug),
      ),
    );
  }

  // ---- Search history handlers (local storage only — no Firestore) -------

  /// Tap a history entry → fill the search box and run the query.
  Future<void> _onTapHistory(String query) async {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    await _search();
  }

  /// Remove a single entry from history (the X button on each row).
  Future<void> _onDeleteHistory(String query) async {
    await _historyService.remove(query);
  }

  /// Clear all entries from history (the "Clear All" button).
  Future<void> _onClearAllHistory() async {
    await _historyService.clear();
  }

  void _showFilterBottomSheet() {
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Title row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          appConfig.translate('filters'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedGenre = null;
                              _selectedType = null;
                              _selectedYear = null;
                              _selectedRating = null;
                              _sortBy = 'latest';
                            });
                          },
                          child: Text(
                            appConfig.translate('clear_filters'),
                            style: TextStyle(color: const Color(0xFFE50914)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Filter content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // Type filter
                        _buildFilterSection(
                          title: appConfig.translate('type_all') == 'All'
                              ? 'Type'
                              : 'အမျိုးအစား',
                          child: _buildTypeSelector(appConfig, setModalState),
                        ),

                        const SizedBox(height: 20),

                        // Genre filter
                        _buildFilterSection(
                          title: appConfig.translate('genres'),
                          child: _buildGenreSelector(appConfig, theme, setModalState),
                        ),

                        const SizedBox(height: 20),

                        // Year filter
                        _buildFilterSection(
                          title: appConfig.translate('year'),
                          child: _buildYearSelector(appConfig, theme, setModalState),
                        ),

                        const SizedBox(height: 20),

                        // Rating filter
                        _buildFilterSection(
                          title: appConfig.translate('min_rating'),
                          child: _buildRatingSelector(appConfig, theme, setModalState),
                        ),

                        const SizedBox(height: 20),

                        // Sort By
                        _buildFilterSection(
                          title: appConfig.translate('sort_by'),
                          child: _buildSortSelector(appConfig, setModalState),
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),

                  // Apply button
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _search();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            appConfig.translate('apply_filters'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterSection({required String title, required Widget child}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildTypeSelector(AppConfig appConfig, StateSetter setModalState) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final types = [
      {'value': null, 'label': appConfig.translate('type_all')},
      {'value': 'movie', 'label': appConfig.translate('type_movie')},
      {'value': 'series', 'label': appConfig.translate('type_series')},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((type) {
        final isSelected = _selectedType == type['value'];
        return ChoiceChip(
          label: Text(type['label'] as String),
          selected: isSelected,
          onSelected: (selected) {
            setModalState(() {
              _selectedType = selected ? type['value'] as String? : null;
            });
          },
          selectedColor: const Color(0xFFE50914).withOpacity(0.2),
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFFE50914) : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFFE50914)
                : (isDark ? Colors.white24 : Colors.grey.shade400),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGenreSelector(AppConfig appConfig, ThemeData theme, StateSetter setModalState) {
    final isDark = theme.brightness == Brightness.dark;
    if (_genres.isEmpty) {
      return Text(
        appConfig.translate('loading'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _genres.map((genre) {
        final isSelected = _selectedGenre == genre.name;
        return ChoiceChip(
          label: Text(genre.name),
          selected: isSelected,
          onSelected: (selected) {
            setModalState(() {
              _selectedGenre = selected ? genre.name : null;
            });
          },
          selectedColor: const Color(0xFFE50914).withOpacity(0.2),
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFFE50914) : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFFE50914)
                : (isDark ? Colors.white24 : Colors.grey.shade400),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildYearSelector(AppConfig appConfig, ThemeData theme, StateSetter setModalState) {
    final isDark = theme.brightness == Brightness.dark;
    if (_years.isEmpty) {
      return Text(
        appConfig.translate('loading'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _years.length + 1, // +1 for "All"
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final year = isAll ? null : _years[index - 1];
          final isSelected = isAll ? _selectedYear == null : _selectedYear == year;
          final label = isAll ? appConfig.translate('type_all') : year!;

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (selected) {
              setModalState(() {
                _selectedYear = isAll ? null : (selected ? year : null);
              });
            },
            selectedColor: const Color(0xFFE50914).withOpacity(0.2),
            backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
            labelStyle: TextStyle(
              color: isSelected ? const Color(0xFFE50914) : isDark ? Colors.white70 : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFFE50914)
                  : isDark ? Colors.white24 : Colors.grey.shade400,
            ),
          );
        },
      ),
    );
  }

  Widget _buildRatingSelector(AppConfig appConfig, ThemeData theme, StateSetter setModalState) {
    final isDark = theme.brightness == Brightness.dark;
    final ratings = ['5', '6', '7', '8', '9'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // All option
        ChoiceChip(
          label: Text(appConfig.translate('type_all')),
          selected: _selectedRating == null,
          onSelected: (selected) {
            setModalState(() {
              _selectedRating = null;
            });
          },
          selectedColor: const Color(0xFFE50914).withOpacity(0.2),
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
          labelStyle: TextStyle(
            color: _selectedRating == null ? const Color(0xFFE50914) : isDark ? Colors.white70 : Colors.black87,
            fontWeight: _selectedRating == null ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: _selectedRating == null
                ? const Color(0xFFE50914)
                : isDark ? Colors.white24 : Colors.grey.shade400,
          ),
        ),
        ...ratings.map((rating) {
          final isSelected = _selectedRating == rating;
          return ChoiceChip(
            label: Text('$rating+'),
            selected: isSelected,
            onSelected: (selected) {
              setModalState(() {
                _selectedRating = selected ? rating : null;
              });
            },
            selectedColor: const Color(0xFFE50914).withOpacity(0.2),
            backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
            labelStyle: TextStyle(
              color: isSelected ? const Color(0xFFE50914) : isDark ? Colors.white70 : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFFE50914)
                  : isDark ? Colors.white24 : Colors.grey.shade400,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSortSelector(AppConfig appConfig, StateSetter setModalState) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sortOptions = [
      {'value': 'latest', 'label': appConfig.translate('sort_latest'), 'icon': Icons.schedule},
      {'value': 'rating', 'label': appConfig.translate('sort_rating'), 'icon': Icons.star},
      {'value': 'name', 'label': appConfig.translate('sort_name'), 'icon': Icons.sort_by_alpha},
    ];

    return Row(
      children: sortOptions.map((option) {
        final isSelected = _sortBy == option['value'];
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setModalState(() {
                _sortBy = option['value'] as String;
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFE50914).withOpacity(0.15)
                    : isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFE50914)
                      : isDark ? Colors.white24 : Colors.grey.shade400,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    option['icon'] as IconData,
                    size: 20,
                    color: isSelected
                        ? const Color(0xFFE50914)
                        : theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : isDark ? Colors.white70 : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar with Filter button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
                    onPressed: () => Navigator.pop(context),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                  const SizedBox(width: 4),
                  // Search field
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      // Use default Flutter behavior: double-tap to select word +
                      // show Cut/Copy/Paste toolbar. This works repeatably — every
                      // double-tap re-shows the toolbar.
                      decoration: InputDecoration(
                        hintText: appConfig.translate('search_hint'),
                        prefixIcon: const Icon(Icons.search, size: 22),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 22),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _results = [];
                                    _hasSearched = false;
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Filter button
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: _hasActiveFilters
                              ? const Color(0xFFE50914).withOpacity(0.15)
                              : isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                          border: _hasActiveFilters
                              ? Border.all(color: const Color(0xFFE50914), width: 1.5)
                              : null,
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.tune,
                            color: _hasActiveFilters
                                ? const Color(0xFFE50914)
                                : theme.colorScheme.onSurface.withOpacity(0.6),
                            size: 24,
                          ),
                          onPressed: _isLoadingFilters ? null : _showFilterBottomSheet,
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        ),
                      ),
                      if (_hasActiveFilters)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE50914),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Active filter chips
            if (_hasActiveFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (_selectedGenre != null)
                            _buildActiveFilterChip(
                              label: _selectedGenre!,
                              onRemove: () => _removeFilter('genre'),
                              theme: theme,
                            ),
                          if (_selectedType != null)
                            _buildActiveFilterChip(
                              label: _selectedType == 'movie'
                                  ? appConfig.translate('type_movie')
                                  : appConfig.translate('type_series'),
                              onRemove: () => _removeFilter('type'),
                              theme: theme,
                            ),
                          if (_selectedYear != null)
                            _buildActiveFilterChip(
                              label: _selectedYear!,
                              onRemove: () => _removeFilter('year'),
                              theme: theme,
                            ),
                          if (_selectedRating != null)
                            _buildActiveFilterChip(
                              label: '${_selectedRating}+ ★',
                              onRemove: () => _removeFilter('rating'),
                              theme: theme,
                            ),
                          if (_sortBy != 'latest')
                            _buildActiveFilterChip(
                              label: _sortBy == 'rating'
                                  ? appConfig.translate('sort_rating')
                                  : appConfig.translate('sort_name'),
                              onRemove: () {
                                setState(() => _sortBy = 'latest');
                                _search();
                              },
                              theme: theme,
                            ),
                          // Clear all button
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ActionChip(
                              label: Text(
                                appConfig.translate('clear_filters'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFE50914),
                                ),
                              ),
                              onPressed: _clearFilters,
                              backgroundColor: const Color(0xFFE50914).withOpacity(0.1),
                              side: const BorderSide(color: Color(0xFFE50914), width: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Results Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _hasSearched && _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                appConfig.translate('no_results'),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : !_hasSearched
                          ? (_searchController.text.trim().isEmpty && !_hasActiveFilters)
                              ? _buildSearchHistoryView(appConfig, theme, isDark)
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.movie_filter_outlined,
                                        size: 64,
                                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        appConfig.translate('search_hint'),
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        appConfig.translate('filters'),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface.withOpacity(0.3),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Icon(
                                        Icons.tune,
                                        size: 32,
                                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                                      ),
                                    ],
                                  ),
                                )
                          : GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.53,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              itemCount: _results.length + (_isLoadingMore ? 6 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _results.length) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final movie = _results[index];
                                return MovieCard(
                                  movie: movie,
                                  onTap: () => _navigateToDetail(movie),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip({
    required String label,
    required VoidCallback onRemove,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFE50914),
          ),
        ),
        deleteIcon: const Icon(Icons.close, size: 16, color: Color(0xFFE50914)),
        onDeleted: onRemove,
        backgroundColor: const Color(0xFFE50914).withOpacity(0.1),
        side: const BorderSide(color: Color(0xFFE50914), width: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsets.only(left: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ---- Search history UI (local-only — backed by SharedPreferences) ------

  /// Renders the recent-searches panel. Shown only when the search box is
  /// empty AND there are no active filters (so users see history on first
  /// entry into the screen). Each row has a clock icon, the query text, and
  /// a small X button to remove that single entry. A header row also has a
  /// "Clear All" button on the right.
  Widget _buildSearchHistoryView(
      AppConfig appConfig, ThemeData theme, bool isDark) {
    final history = _searchHistory;
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              appConfig.translate('search_hint'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appConfig.translate('filters'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.tune,
              size: 32,
              color: theme.colorScheme.onSurface.withOpacity(0.2),
            ),
          ],
        ),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      children: [
        // Header row: "Recent Searches" + Clear All button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appConfig.translate('search_history'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: subTextColor,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
              TextButton(
                onPressed: _onClearAllHistory,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  appConfig.translate('search_history_clear_all'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // History rows
        for (final q in history) _buildHistoryItem(q, textColor, isDark, theme),
      ],
    );
  }

  Widget _buildHistoryItem(
      String query, Color textColor, bool isDark, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTapHistory(query),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 20,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Single-item delete button (X on the right)
              InkWell(
                onTap: () => _onDeleteHistory(query),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
