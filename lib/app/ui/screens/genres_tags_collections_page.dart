import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';

class GenresTagsCollectionsPage extends StatefulWidget {
  const GenresTagsCollectionsPage({super.key});

  @override
  State<GenresTagsCollectionsPage> createState() =>
      _GenresTagsCollectionsPageState();
}

class _GenresTagsCollectionsPageState extends State<GenresTagsCollectionsPage>
    with TickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];
  bool _isLoading = true;

  // Sub-tab controllers for Genres and Tags only.
  // (Phase 4.25.2 — Collections sub-tabs removed by Bro's request;
  // a single grid now shows all collections. The FilterResultPage will
  // display both movies and series for the tapped collection.)
  late TabController _genresSubTabController;
  late TabController _tagsSubTabController;

  // Phase 4.25 — Collections tab UX: search + sort.
  // Search lets users quickly find "Marvel" / "DC" / "Harry Potter" when
  // the collection list grows long. Sort lets them order by A→Z, Z→A, or
  // Most Movies (moviesCount desc).
  // Phase 4.25.2 — search is auto-cleared when returning from
  // FilterResultPage so the user lands back on a fresh list (Bro's
  // complaint: "Search ကို Auto နိုပ်ထားသလိုဖြစ်နေပါတယ်").
  final TextEditingController _collectionSearchController = TextEditingController();
  String _collectionSearchQuery = '';
  // 'az' | 'za' | 'most' — default 'az' for predictable alphabetical browsing.
  String _collectionSortBy = 'az';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _genresSubTabController = TabController(length: 2, vsync: this);
    _tagsSubTabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _genresSubTabController.dispose();
    _tagsSubTabController.dispose();
    _collectionSearchController.dispose();
    super.dispose();
  }

  /// Phase 4.25.2 — Clears the Collections search field and unfocuses.
  /// Called when the user returns from FilterResultPage so the list
  /// shows all collections again (not the previous filtered subset).
  void _clearCollectionSearch() {
    _collectionSearchController.clear();
    setState(() => _collectionSearchQuery = '');
    // Drop keyboard focus so it doesn't pop back up on return.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _loadData() async {
    try {
      List<TagAndGenres> genres = [];
      List<TagAndGenres> tags = [];
      List<TagAndGenres> collections = [];

      // PARALLEL FETCH — previously sequential (genres → tags → collections),
      // adding 3 × query latency on slow networks. Now all three fire in
      // parallel; total wait ≈ slowest query instead of sum of all three.
      // (Task 36 #2 — see movies_page.dart for the artificial-skeleton-floor
      // removal rationale; that pattern was also removed here.)
      final results = await Future.wait([
        _contentService.getGenres().catchError((e) {
          debugPrint('Error loading genres: $e');
          return <TagAndGenres>[];
        }),
        _contentService.getTags().catchError((e) {
          debugPrint('Error loading tags: $e');
          return <TagAndGenres>[];
        }),
        _contentService.getCollections().catchError((e) {
          debugPrint('Error loading collections: $e');
          return <TagAndGenres>[];
        }),
      ]);

      genres = results[0] as List<TagAndGenres>;
      tags = results[1] as List<TagAndGenres>;
      collections = results[2] as List<TagAndGenres>;

      if (mounted) {
        setState(() {
          _genres = genres;
          _tags = tags;
          _collections = collections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('genres_tags_collections')),
        bottom: TabBar(
          controller: _tabController,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            Tab(text: appConfig.translate('genres')),
            Tab(text: appConfig.translate('tags')),
            Tab(text: appConfig.translate('collections')),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGenresTab(appConfig, theme),
                _buildTagsTab(appConfig, theme),
                _buildCollectionsTab(appConfig, theme),
              ],
            ),
    );
  }

  // ==================== GENRES TAB (with Movies/Series sub-tabs) ====================
  Widget _buildGenresTab(AppConfig appConfig, ThemeData theme) {
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _genresSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Movies'),
              Tab(text: 'Series'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _genresSubTabController,
            children: [
              // Movies Genres
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Movies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _genres.map((g) => g.name).toList(),
                        filterType: 'genre', typeFilter: 'movie'),
                  ],
                ),
              ),
              // Series Genres
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Series',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _genres.map((g) => g.name).toList(),
                        filterType: 'genre', typeFilter: 'series'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TAGS TAB (with Movies/Series sub-tabs) ====================
  Widget _buildTagsTab(AppConfig appConfig, ThemeData theme) {
    if (_tags.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tagsSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Movies'),
              Tab(text: 'Series'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tagsSubTabController,
            children: [
              // Movies Tags
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Movies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _tags.map((t) => t.name).toList(),
                        filterType: 'tag', typeFilter: 'movie'),
                  ],
                ),
              ),
              // Series Tags
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Series',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _tags.map((t) => t.name).toList(),
                        filterType: 'tag', typeFilter: 'series'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== COLLECTIONS TAB (Phase 4.25.2 — no sub-tabs) ====================
  //
  // Phase 4.25 originally added Movies/Series sub-tabs to mirror Genres
  // and Tags. Bro reported he doesn't want them on Collections — the
  // collection list itself is the same regardless of type, and the
  // sub-tabs just added an extra tap. They've been removed.
  //
  // What remains: search bar + sort dropdown + a single lazy grid.
  // Tapping a collection navigates to FilterResultPage with NO
  // typeFilter (so both movies and series for that collection are shown).
  //
  // Phase 4.25.2 — search auto-clears on return from FilterResultPage
  // (Bro's complaint about "Marvel" staying in the search field after
  // coming back). The grid resets to showing all collections, and the
  // keyboard hides via FocusManager.unfocus().
  Widget _buildCollectionsTab(AppConfig appConfig, ThemeData theme) {
    if (_collections.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // ---- Search + sort bar ----
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: TextField(
                  controller: _collectionSearchController,
                  onChanged: (value) {
                    setState(() => _collectionSearchQuery = value.trim());
                  },
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: appConfig.translate('search_collections'),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      size: 20,
                    ),
                    suffixIcon: _collectionSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            onPressed: _clearCollectionSearch,
                          )
                        : null,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF1A1A1A)
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE50914), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort dropdown
              _buildCollectionSortDropdown(appConfig, theme),
            ],
          ),
        ),
        // ---- Grid (lazy, single — no sub-tabs) ----
        Expanded(
          child: _buildCollectionGrid(appConfig, theme),
        ),
      ],
    );
  }

  /// Sort dropdown for the Collections tab. Compact icon-button style
  /// that opens a popup menu — keeps the search bar visually dominant
  /// while still surfacing all three sort options.
  Widget _buildCollectionSortDropdown(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final options = <(String value, String labelKey, IconData icon)>[
      ('az', 'sort_a_to_z', Icons.arrow_downward),
      ('za', 'sort_z_to_a', Icons.arrow_upward),
      ('most', 'sort_most_movies', Icons.trending_up),
    ];
    final current =
        options.firstWhere((o) => o.$1 == _collectionSortBy, orElse: () => options.first);

    return PopupMenuButton<String>(
      tooltip: appConfig.translate('sort_by'),
      onSelected: (value) {
        setState(() => _collectionSortBy = value);
      },
      itemBuilder: (context) => options
          .map((o) => PopupMenuItem<String>(
                value: o.$1,
                child: Row(
                  children: [
                    Icon(o.$3,
                        size: 18,
                        color: o.$1 == _collectionSortBy
                            ? const Color(0xFFE50914)
                            : theme.colorScheme.onSurface.withOpacity(0.6)),
                    const SizedBox(width: 10),
                    Text(
                      appConfig.translate(o.$2),
                      style: TextStyle(
                        color: o.$1 == _collectionSortBy
                            ? const Color(0xFFE50914)
                            : theme.colorScheme.onSurface,
                        fontWeight: o.$1 == _collectionSortBy
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(current.$3,
                size: 16, color: const Color(0xFFE50914)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  /// Builds the lazy GridView for the Collections tab.
  /// Filtering, sorting, and section headers all happen here.
  ///
  /// Phase 4.25.2 — no longer takes a `typeFilter` param. Tapping a
  /// card navigates to FilterResultPage with typeFilter=null, so both
  /// movies and series are shown for the tapped collection.
  Widget _buildCollectionGrid(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // 1. Apply search filter (case-insensitive substring match)
    List<TagAndGenres> filtered = _collections;
    if (_collectionSearchQuery.isNotEmpty) {
      final q = _collectionSearchQuery.toLowerCase();
      filtered = filtered
          .where((c) => c.name.toLowerCase().contains(q))
          .toList();
    }

    // 2. Apply sort
    final sorted = List<TagAndGenres>.from(filtered);
    switch (_collectionSortBy) {
      case 'az':
        sorted.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'za':
        sorted.sort((a, b) =>
            b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'most':
        sorted.sort((a, b) => (b.moviesCount ?? 0).compareTo(a.moviesCount ?? 0));
        break;
    }

    // 3. Empty state
    if (sorted.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 56,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              appConfig.translate('no_results'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    // 4. Section headers only for alphabetical sorts (not for 'most')
    final useSectionHeaders = _collectionSortBy == 'az' || _collectionSortBy == 'za';

    // 5. Build a flat item list where section headers are interleaved
    //    with collection cards. Each entry is either a header or a card.
    final items = <_CollectionListItem>[];
    if (useSectionHeaders) {
      String? lastSection;
      for (final c in sorted) {
        final firstChar = _sectionKeyFor(c.name);
        if (firstChar != lastSection) {
          items.add(_CollectionListItem.header(firstChar));
          lastSection = firstChar;
        }
        items.add(_CollectionListItem.card(c));
      }
    } else {
      for (final c in sorted) {
        items.add(_CollectionListItem.card(c));
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        // Taller tiles (1.6 aspect ratio) give room for the avatar +
        // name + count badge without cramping.
        childAspectRatio: 1.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              item.headerLabel!,
              style: TextStyle(
                color: const Color(0xFFE50914),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          );
        }
        final collection = item.collection!;
        return _CollectionCard(
          name: collection.name,
          count: collection.moviesCount,
          isDark: isDark,
          // Phase 4.25.2 — navigate + auto-clear search on return.
          onTap: () async {
            // Drop keyboard focus before navigating so it doesn't pop
            // back up awkwardly when FilterResultPage appears.
            FocusManager.instance.primaryFocus?.unfocus();
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FilterResultPage(
                  title: collection.name,
                  // No typeFilter — show both movies and series.
                  collectionName: collection.name,
                ),
              ),
            );
            // After the user comes back, clear the search field so the
            // list shows all collections (Bro's complaint: previously
            // the search query "Marvel" stayed typed and only Marvel
            // was visible, which felt confusing).
            if (mounted) _clearCollectionSearch();
          },
        );
      },
    );
  }

  /// Returns the section header key for a collection name.
  /// Returns the first uppercase letter (digits/symbols → '#').
  static String _sectionKeyFor(String name) {
    if (name.isEmpty) return '#';
    final c = name[0].toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(c)) return c;
    return '#';
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildNeonGrid(ThemeData theme, List<String> items,
      {required String filterType, String? typeFilter}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _NeonGlowButton(
          title: item,
          isSolid: filterType == 'collection',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FilterResultPage(
                  title: item,
                  genreName: filterType == 'genre' ? item : null,
                  tagName: filterType == 'tag' ? item : null,
                  collectionName: filterType == 'collection' ? item : null,
                  typeFilter: typeFilter,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==================== COLLECTIONS TAB — Phase 4.25 helpers ====================

/// Lightweight wrapper used by the Collections tab's flat item list.
/// Each entry is either a section header (e.g. "M" for Marvel) or a
/// collection card. Using a single list type lets us interleave headers
/// and cards in one `GridView.builder` without managing two parallel
/// data structures.
class _CollectionListItem {
  final bool isHeader;
  final String? headerLabel;
  final TagAndGenres? collection;

  const _CollectionListItem._({
    required this.isHeader,
    this.headerLabel,
    this.collection,
  });

  factory _CollectionListItem.header(String label) =>
      _CollectionListItem._(isHeader: true, headerLabel: label);
  factory _CollectionListItem.card(TagAndGenres c) =>
      _CollectionListItem._(isHeader: false, collection: c);
}

/// Phase 4.25 — Collection card.
///
/// Replaces the old solid-red `_NeonGlowButton` for the Collections tab.
/// Each card has:
///   - A circular avatar with the first letter of the collection name
///     (Marvel → "M", DC → "D"). This gives users an instant visual
///     anchor when scanning a long list — far better than the old
///     identical red rectangles.
///   - The full collection name (max 2 lines, ellipsis).
///   - An optional movies-count badge when `moviesCount` is non-null
///     and > 0. Helps users spot the biggest collections.
///   - A subtle red gradient background with a dark-to-darker shade in
///     dark mode, and a light-to-white gradient in light mode. Keeps
///     the Netflix-red brand identity without being a flat slab.
///
/// Phase 4.25.2 — card no longer owns its navigation logic. Instead,
/// the parent passes an `onTap` callback, which lets the parent do
/// post-navigation cleanup (clearing the search field on return).
/// The card just handles its own pressed/animation state.
class _CollectionCard extends StatefulWidget {
  final String name;
  final int? count;
  final bool isDark;
  /// Called when the user taps the card. The parent owns navigation.
  final Future<void> Function()? onTap;

  const _CollectionCard({
    required this.name,
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _isPressed = false;

  String get _initial {
    if (widget.name.isEmpty) return '?';
    return widget.name[0].toUpperCase();
  }

  // Stable hue derived from the collection name → each collection gets
  // a consistent avatar color tint. Marvel and DC won't look identical,
  // and the same collection keeps its color across rebuilds.
  Color get _avatarColor {
    // Simple hash → hue. No fancy crypto needed.
    int hash = 0;
    for (final c in widget.name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    // Restrict hue to warm red-orange-pink range (0–50, 330–360) so
    // avatars stay on-brand with the Netflix-red palette.
    final hue = (hash % 80).toDouble();
    return HSLColor.fromAHSL(
      1.0,
      hue < 30 ? hue + 350 : hue,
      0.65,
      0.55,
    ).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final hasCount = (widget.count ?? 0) > 0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          // Subtle diagonal gradient — gives the card depth without
          // being loud. The pressed state lifts the red a touch.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDark
                ? [
                    const Color(0xFF2A2A2A),
                    const Color(0xFF1A1A1A),
                  ]
                : [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isPressed
                ? const Color(0xFFE50914)
                : widget.isDark
                    ? Colors.white12
                    : Colors.grey.shade300,
            width: _isPressed ? 1.5 : 1,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFFE50914).withOpacity(0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Avatar circle with the first letter
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _avatarColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _avatarColor.withOpacity(0.4),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + count
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    // Phase 4.25.2 — count badge is now type-agnostic
                    // (just shows the number with a movie icon) since
                    // we no longer have a Movies/Series sub-tab to
                    // tell us which type the count refers to.
                    if (hasCount) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.movie_outlined,
                              size: 10,
                              color: Color(0xFFE50914),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${widget.count}',
                              style: const TextStyle(
                                color: Color(0xFFE50914),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== NEON GLOW BUTTON (Netflix Red) ====================

class _NeonGlowButton extends StatefulWidget {
  final String title;
  final bool isSolid;
  final VoidCallback? onTap;

  const _NeonGlowButton({
    required this.title,
    this.isSolid = false,
    this.onTap,
  });

  @override
  State<_NeonGlowButton> createState() => _NeonGlowButtonState();
}

class _NeonGlowButtonState extends State<_NeonGlowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovering = true),
      onTapUp: (_) => setState(() => _isHovering = false),
      onTapCancel: () => setState(() => _isHovering = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isSolid
              ? const Color(0xFFE50914)
              : isDark
                  ? const Color(0xFF1A1A1A)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: widget.isSolid
              ? null
              : Border.all(
                  color: _isHovering
                      ? const Color(0xFFE50914)
                      : isDark
                          ? Colors.white24
                          : Colors.grey.shade400,
                  width: 1.5,
                ),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                    color: const Color(0xFFE50914).withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : widget.isSolid
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isSolid
                    ? Colors.white
                    : isDark
                        ? Colors.white
                        : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: _isHovering
                    ? [
                        Shadow(
                          color: const Color(0xFFE50914).withOpacity(0.8),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== FILTER RESULT PAGE (public) ====================
class FilterResultPage extends StatefulWidget {
  final String title;
  final String? genreName;
  final String? tagName;
  final String? collectionName;
  final String? typeFilter; // 'movie' or 'series'

  const FilterResultPage({
    super.key,
    required this.title,
    this.genreName,
    this.tagName,
    this.collectionName,
    this.typeFilter,
  });

  @override
  State<FilterResultPage> createState() => _FilterResultPageState();
}

class _FilterResultPageState extends State<FilterResultPage> {
  final FirestoreContentService _contentService = FirestoreContentService();

  List<Movie> _movies = [];
  List<Movie> _filteredMovies = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  // Track seen IDs to prevent duplicates
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
      _seenIds.clear();
    });
    try {
      Map<String, dynamic> result;
      if (widget.genreName != null) {
        result = await _contentService.getMoviesByGenre(
          widget.genreName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(
          widget.tagName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(
          widget.collectionName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else {
        result = await _contentService.getMovies(limit: 20); // PAGINATION: 20/page
      }

      if (mounted) {
        final allMovies = result['movies'] as List<Movie>;

        // Track IDs to prevent future duplicates
        for (final m in allMovies) {
          _seenIds.add(m.id);
        }

        // Apply type filter if specified (Movies or Series sub-tab)
        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = allMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = allMovies;
        }

        // NOTE: previously had an artificial 600ms skeleton floor here.
        // Removed in Task 36 #2 — see movies_page.dart for the rationale.
        setState(() {
          _movies = allMovies;
          _filteredMovies = filtered;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });

        // Task 38 Req 5 — post-frame auto-load safety net.
        // If the first page returned fewer items than would fill the
        // viewport (e.g., on a large tablet showing 30+ items per screen,
        // or a genre with exactly 20 docs that doesn't fill the screen),
        // the scroll listener never fires — and infinite scroll silently
        // dies. Schedule a `_loadMore()` on the next frame; `_loadMore`
        // will no-op if `_hasMore` is already false (e.g., the genre only
        // had 20 docs total).
        if (_hasMore && _filteredMovies.length < 30) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('FilterResultPage load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      Map<String, dynamic> result;
      if (widget.genreName != null) {
        result = await _contentService.getMoviesByGenre(
          widget.genreName!, limit: 20, startAfter: _lastDoc,
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(
          widget.tagName!, limit: 20, startAfter: _lastDoc,
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(
          widget.collectionName!, limit: 20, startAfter: _lastDoc,
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else {
        result = await _contentService.getMovies(limit: 20, startAfter: _lastDoc);
      }

      if (mounted) {
        final newMovies = result['movies'] as List<Movie>;

        // Deduplicate by ID to prevent duplicates
        final dedupedMovies = <Movie>[];
        for (final m in newMovies) {
          if (!_seenIds.contains(m.id)) {
            _seenIds.add(m.id);
            dedupedMovies.add(m);
          }
        }

        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = dedupedMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = dedupedMovies;
        }

        setState(() {
          _movies.addAll(dedupedMovies);
          _filteredMovies.addAll(filtered);
          // Task 39 — stop paginating when dedup returns 0 items, which
          // happens when Firestore returned a page of docs we've already
          // seen (e.g., the fallback path returned page 1 again before
          // the startAfterDocument fix was deployed, or the genre has
          // fewer than `limit` total docs and Firestore returned the
          // same set with a slightly different doc-ID order). Without
          // this guard, the auto-load safety net would spin forever
          // calling _loadMore → 0 new docs → _hasMore stays true →
          // another _loadMore → ad infinitum (and burn Firestore reads).
          _hasMore = (result['hasMore'] as bool) && dedupedMovies.isNotEmpty;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });

        // Task 38 Req 5 — chained auto-load safety net (mirror of the one
        // in _loadMovies). If after a `_loadMore` we still have fewer
        // than 30 visible items AND `_hasMore` is still true, the grid
        // likely still doesn't fill the viewport — schedule another
        // `_loadMore` on the next frame. Caps infinite recursion because
        // `_loadMore` no-ops once `_hasMore` flips false (Firestore
        // returned fewer than `limit` docs).
        if (_hasMore && _filteredMovies.length < 30) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? _buildSkeletonGrid()
          : RefreshIndicator(
              onRefresh: _loadMovies,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  // Task 38 Req 5 — trigger at 80% scroll instead of 100%
                  // so the next page kicks in BEFORE the user hits the
                  // bottom (smoother infinite scroll). Combined with the
                  // post-frame auto-load below, this also handles the case
                  // where the first page didn't even fill the viewport
                  // (e.g., on a large tablet).
                  final trigger = scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent * 0.8;
                  if (trigger && !_isLoadingMore && _hasMore) {
                    _loadMore();
                  }
                  return false;
                },
                child: _filteredMovies.isEmpty
                    ? Center(
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
                              'No ${widget.title} yet',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.53,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: _filteredMovies.length + (_isLoadingMore ? 6 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _filteredMovies.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final movie = _filteredMovies[index];
                          return MovieCard(
                            movie: movie,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => movie.type == 'series'
                                      ? SeriesDetailScreen(slug: movie.slug)
                                      : MovieDetailScreen(slug: movie.slug),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return const MovieCardSkeleton();
      },
    );
  }
}
