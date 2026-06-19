---
Task ID: 4
Agent: General Purpose
Task: Expandable Season & Episode Manager for Series Edit page

Work Log:

Change 1: Updated Episode model with videoUrl and downloadUrl fields
- lib/app/core/models/movie_detail.dart:
  - Added `final String? videoUrl;` field to Episode class
  - Added `final String? downloadUrl;` field to Episode class
  - Updated constructor with optional `this.videoUrl` and `this.downloadUrl` parameters
  - Updated fromMap: `videoUrl: map['videoUrl'] as String?`, `downloadUrl: map['downloadUrl'] as String?`
  - Updated toMap: Conditionally includes `videoUrl` and `downloadUrl` only when not null (avoids writing null fields to Firestore)
  - Existing `downloadLinks` list preserved for backward compatibility with complex download link management
  - Backward compatible: existing code using `Episode(name: ...)` still works since new fields are nullable/optional

Change 2: Added _EpisodeControllers helper class and controller management
- lib/app/ui/screens/edit_movie_page.dart:
  - Added `_EpisodeControllers` class with `title`, `videoUrl`, `downloadUrl` TextEditingControllers and a `dispose()` method
  - Added `Map<int, Map<int, _EpisodeControllers>> _episodeControllers = {}` state variable for nested controller storage (seasonIndex -> episodeIndex -> controllers)
  - Added `_disposeAllEpisodeControllers()`: iterates and disposes all controllers, clears map
  - Added `_initEpisodeControllers()`: creates controllers from loaded episode data, called in `_loadData()` after `_seasons` is populated
  - Added `_getOrCreateControllers(int seasonIndex, int episodeIndex)`: lazily creates controllers if missing
  - Added `_addSeason()`: extracted from inline onPressed, properly initializes controller map for new season
  - Added `_removeSeason(int seasonIndex)`: disposes all controllers for removed season, re-keys remaining seasons in controller map
  - Added `_addEpisode(int seasonIndex)`: adds Episode to model + creates controllers with default values
  - Added `_removeEpisode(int seasonIndex, int episodeIndex)`: disposes controller, re-keys remaining episode controllers
  - Added `_syncControllersToModel()`: reads text from all controllers and updates Episode objects in `_seasons` list before saving

Change 3: Replaced Card-based seasons UI with ExpansionTile accordion
- Replaced the old Card + Column UI (lines 571-662) with ExpansionTile-based accordion UI
- Each season is wrapped in a Card with `clipBehavior: Clip.antiAlias` containing an ExpansionTile
- Collapsed state shows:
  - Leading icon (Icons.video_library, red accent)
  - Season name (bold, 15px)
  - Episode count subtitle ("X episodes")
  - Delete season button (red trash icon) in trailing
- Expanded state shows:
  - Empty state message when no episodes ("No episodes yet. Add one below.")
  - For each episode: styled Container with:
    - Episode number label + delete button (Row)
    - TextFormField for Episode Title (full width, outlined border, dense)
    - Row with two Expanded TextFormFields for Video URL and Download URL
    - Additional download links count indicator (if downloadLinks list is non-empty)
  - "Add Episode" TextButton at bottom of each expanded season
- "Add Season" OutlinedButton placed after all season tiles

Change 4: Integrated controller sync with save flow
- Added `_syncControllersToModel()` call in `_saveMovie()` before `setState(() => _isSaving = true)`
- This ensures all text controller values are synced to the Episode model before the data is serialized to Firestore
- Updated `dispose()` to call `_disposeAllEpisodeControllers()` for proper cleanup

Change 5: Updated _loadData to initialize controllers
- Added `_initEpisodeControllers()` call after `_seasons` is populated from Firestore data
- Ensures all existing episode data has corresponding controllers on page load

Files Modified:
- lib/app/core/models/movie_detail.dart (Episode model)
- lib/app/ui/screens/edit_movie_page.dart (ExpansionTile UI + controller management)

Backward Compatibility:
- add_series_page.dart: Uses `Episode(name: ...)` — still works, new fields default to null
- tmdb_service.dart: Creates episode maps with `name` + `downloadLinks` — Episode.fromMap handles missing videoUrl/downloadUrl as null
- series_detail_screen.dart: Reads `episode.name` and `episode.downloadLinks` — both still present
- Existing downloadLinks management (bottom sheet dialogs) preserved alongside new inline fields

---

Task ID: 6
Agent: Main Agent
Task: TMDB Generator Optimization - Filter Imported Posts + Batch Sync with Last Sync Date

Work Log:
- Read tmdb_generator_page.dart (1705 lines) to understand full structure
- Identified key areas: _performSearch(), _loadMorePages(), _syncMovies(), _syncSeries(), _buildSyncSection(), _importedTmdbIds

Change 1: Filter Imported Posts from Search Results
- Modified _performSearch() (line ~218): Renamed `results` to `rawResults`, added filter `.where((item) => !_importedTmdbIds.contains(item['id']))` to produce `results` with only NEW/unimported items
- Modified _loadMorePages() (line ~287): Renamed `moreResults` to `rawMoreResults`, added same filter before `_results.addAll()` to keep grid showing only new posts
- Grid now exclusively shows NEW items (not yet in Firestore), eliminating visual clutter of already-imported content

Change 2: Batch Sync (20 posts) with Last Sync Date
- Added state variables: `_syncRemainingMovies`, `_syncRemainingSeries` (int) and `static const int _syncBatchSize = 20`
- Added `_loadSyncRemainingCounts()` method: queries Firestore, counts movies/series without `lastSyncDate` field, sets remaining counts
- Called `_loadSyncRemainingCounts()` in `initState()` to show remaining counts on page load
- Modified `_syncMovies()`:
  - After fetching docs, sorts by `lastSyncDate` (null first = never synced, then oldest first)
  - Takes only first `_syncBatchSize` (20) items via `docs.take(_syncBatchSize)`
  - Sets `_syncRemainingMovies = totalRemaining - batchDocs.length`
  - After each successful sync transaction, adds `safeUpdate['lastSyncDate'] = FieldValue.serverTimestamp()`
  - SnackBar now shows "Movie sync batch complete! ... X remaining to sync"
  - Calls `_loadSyncRemainingCounts()` after sync to refresh counts
  - Dialog text updated: "This will sync up to 20 movies...prioritized by sync date"
- Modified `_syncSeries()`: Same batch logic as _syncMovies():
  - Sorts by lastSyncDate (null first, oldest first)
  - Takes only 20 items per batch
  - Sets `_syncRemainingSeries` after batch
  - Adds `lastSyncDate` timestamp on each successful sync
  - Updated dialog and SnackBar text
  - Calls `_loadSyncRemainingCounts()` after sync
- Updated `_buildSyncSection()` UI:
  - Wrapped each sync button (Sync Movies / Sync Series) in a Column
  - Added conditional "X remaining" text below each button (visible only when count > 0)
  - Styled with small font (10px), subtle color (white54/black54)

Stage Summary:
- Search grid now filters out already-imported TMDB items, showing only NEW content
- Sync operations process max 20 items per batch instead of all at once
- Each synced document gets a `lastSyncDate` timestamp for priority tracking
- Never-synced items are prioritized, then oldest-synced items next
- UI shows "X remaining" count below each sync button
- All existing functionality preserved (import, selection, progress bars, etc.)

---

Task ID: 3
Agent: General Purpose
Task: Post UI Changes - Country emoji format, Views, File Size, Red star icon

Work Log:

Change 1: Country display → "🇺🇸 English" format
- Added `_countryToDisplay(String? code)` helper method to both detail screens
- Method converts 2-letter country code to flag emoji using Unicode regional indicator symbols
- Includes a countryLangMap with 36+ country-to-language mappings (US→English, JP→Japanese, KR→Korean, etc.)
- For unknown codes, displays flag emoji + raw code
- movie_detail_screen.dart: Replaced `Icon(Icons.public) + Text(detail.country!)` with `Text(_countryToDisplay(detail.country))` — removed the globe icon since the flag emoji provides the visual indicator
- series_detail_screen.dart: Added the same Views & Country row (was missing entirely), using `_countryToDisplay()`

Change 2: Views count display with formatting
- movie_detail_screen.dart: Already had `_formatViews()` and the views row — verified it works correctly (1K, 1.2M format)
- series_detail_screen.dart: Added `_formatViews()` method and Views & Country row in the header area, matching the movie detail screen layout

Change 3: File Size field
- movie_detail_screen.dart: Added File Size row in header after Views & Country, with `Icons.sd_storage` icon, only shown when `fileSize` is not null/empty
- series_detail_screen.dart: Added same File Size row with identical styling
- edit_movie_page.dart: Already had `_fileSizeController` and `_countryController` declared/disposed/loaded. Added:
  - `fileSize` and `country` to the save data map
  - UI: File Size + Country row with two TextFormField fields
- add_movie_page.dart: Already had controllers. Added:
  - `fileSize` and `country` to the save data map
  - UI: File Size + Country row with two TextFormField fields

Change 4: Red star icon instead of amber
- movie_detail_screen.dart: Changed `Icon(Icons.star, size: 14, color: Colors.amber)` → `Icon(Icons.star, size: 14, color: Color(0xFFE50914))`
- movie_detail_screen.dart: Changed rating text color from `Colors.amber` → `Color(0xFFE50914)`
- series_detail_screen.dart: Same changes applied for consistency

Files Modified:
- lib/app/ui/screens/movie_detail_screen.dart
- lib/app/ui/screens/series_detail_screen.dart
- lib/app/ui/screens/edit_movie_page.dart
- lib/app/ui/screens/add_movie_page.dart

---

Task ID: 2
Agent: General Purpose
Task: Movies vs Series separate logic in Edit/Add pages + Series poster shows "Season X"

Work Log:

Change 1: Added `seasons` field to Movie model
- lib/app/core/models/movie.dart: Added `final String? seasons;` field
- Constructor: Added `this.seasons` optional parameter
- fromMap: `seasons: map['seasons'] is List ? (map['seasons'] as List).length.toString() : map['seasons']?.toString()` — smart parsing: if Firestore `seasons` is a List (of Season objects), extracts the length as string count; otherwise parses as string
- toMap: Added `'seasons': seasons`

Change 2: Edit Movie page — Format dropdown for Movies, Seasons/Episodes for Series
- lib/app/ui/screens/edit_movie_page.dart:
  - Added `String _format = 'MP4'` state variable
  - _loadData: Set `_format = ['MP4', 'MKV', 'MKV / MP4'].contains(detail.format) ? detail.format! : 'MP4'` (safe validation for dropdown)
  - _saveMovie: `'duration'` now saves null for series; added `'format': _type != 'series' ? _format : null`
  - UI: Replaced generic Duration + Resolution row with conditional sections:
    - For movies (_type != 'series'): Format dropdown (MP4/MKV/MKV / MP4) + Duration + Resolution
    - For series (_type == 'series'): Read-only Seasons count + Episodes count fields + Resolution
  - Duration is no longer shown/collected for series
  - Format is no longer saved for series

Change 3: Add Movie page — Same Format dropdown for Movies
- lib/app/ui/screens/add_movie_page.dart:
  - Added `String _format = 'MP4'` state variable
  - _saveMovie: `'duration'` now saves null for series; added `'format': _type != 'series' ? _format : null`
  - UI: Same conditional layout as Edit Movie page:
    - For movies: Format dropdown + Duration + Resolution
    - For series: Resolution only (no duration field)

Change 4: Add Series page — Removed Duration field
- lib/app/ui/screens/add_series_page.dart:
  - Removed Duration + Resolution row, replaced with Resolution-only field
  - _saveSeries: `'duration': null` and `'format': null` for series

Change 5: MovieCard — Show "Season X" for series, duration for movies
- lib/app/ui/components/movie_card.dart:
  - Expanded the subtitle row below title to show:
    - For series (type == 'series'): TV icon + "Season X" text (where X = movie.seasons)
    - For movies (type != 'series'): Clock icon + "X min" duration text
  - These appear alongside existing year and watch progress indicators

Change 6: Series Detail Screen — "Season X" instead of duration
- lib/app/ui/screens/series_detail_screen.dart:
  - Replaced duration display (clock icon + "X min") in header with TV icon + "Season [seasons.length]"
  - Uses `detail.seasons.isNotEmpty` check instead of `detail.duration` check

Files Modified:
- lib/app/core/models/movie.dart
- lib/app/ui/screens/edit_movie_page.dart
- lib/app/ui/screens/add_movie_page.dart
- lib/app/ui/screens/add_series_page.dart
- lib/app/ui/components/movie_card.dart
- lib/app/ui/screens/series_detail_screen.dart

---

Task ID: 7
Agent: Main Agent
Task: Part 2 - Skeleton Loading, Admin Edit Buttons, Format Dropdown, Video Player Caching

Work Log:

Change 1: Skeleton Loading improvements
- movies_page.dart: Added minimum 600ms display time for skeleton (Stopwatch + Future.delayed)
- series_page.dart: Same minimum 600ms skeleton display time
- genres_tags_collections_page.dart: Removed _GenreButtonSkeleton class entirely, replaced with simple CircularProgressIndicator, added 500ms minimum display
- FilterResultPage: Added minimum 600ms skeleton display time

Change 2: Admin Panel - Format Dropdown & Series Fields
- edit_movie_page.dart:
  - Added `String _format = 'MP4'` state variable
  - Format field changed from TextFormField to DropdownButtonFormField with options: MP4, MKV, MKV / MP4
  - Duration field only shown for movies (_type != 'series')
  - Series: Replaced Duration with read-only Seasons/Episodes count + Resolution row
  - Save method: duration/fileSize/format are null for series; format uses _format dropdown variable
  - _loadData: Sets _format from loaded detail.format with safe validation

Change 3: Admin Panel - Edit Buttons for Download/Watch Links
- edit_movie_page.dart - Movies:
  - Added Edit icon button (blue/white) next to Delete icon (red) for Download Links
  - Added Edit icon button for Watch Links
  - Added _showEditDownloadLinkModal(index): Pre-filled modal with existing Server/Quality/Size/URL, Update button overwrites original
  - Added _showEditWatchLinkModal(index): Same pattern for watch links
- edit_movie_page.dart - Series:
  - Episode edit dialog: Added Edit icon for download links and watch links in each episode
  - Added _showEditEpisodeDownloadLinkDialog(seasonIndex, episodeIndex, linkIndex): Pre-filled modal, Update overwrites
  - Added _showEditEpisodeWatchLinkDialog(seasonIndex, episodeIndex, linkIndex): Same pattern

Change 4: Video Player Network Caching Optimization
- video_player_screen.dart:
  - Added mpv network caching properties: cache=yes, cache-secs=5, cache-pause=yes
  - cache-pause-wait=3 (wait up to 3s for cache to fill before resuming)
  - cache-pause-initial=yes (pause at start until cache fills)
  - demuxer-max-bytes=50MB (forward buffer for all devices)
  - demuxer-max-back-bytes=25MB (back buffer for all devices)
  - Increased PlayerConfiguration bufferSizeBytes: 32MB/48MB/64MB/96MB by tier (was 16/24/32/50)
- android/app/build.gradle: Verified minSdk=23 (≥21 requirement met)

Stage Summary:
- Skeleton loading now shows for minimum 600ms to prevent flash
- Genres/Tags/Collections skeleton removed, simple loading indicator instead
- Format dropdown (MP4/MKV/MKV MP4) replaces text field for movies
- Series: Duration replaced with Seasons/Episodes read-only fields
- Edit buttons added to all Download/Watch links (Movies + Series)
- Video player has 5-second network caching for smooth MKV 1080p streaming
- All changes pushed to GitHub Main branch

Files Modified:
- lib/app/ui/screens/movies_page.dart
- lib/app/ui/screens/series_page.dart
- lib/app/ui/screens/genres_tags_collections_page.dart
- lib/app/ui/screens/edit_movie_page.dart
- lib/app/ui/screens/video_player_screen.dart

---

Task ID: 9
Agent: download-notification-agent
Task: Implement system-level download notifications

Work Log:
- Read existing download_manager_service.dart to understand DownloadTask model, status enum, and all download lifecycle hooks
- Read pubspec.yaml to identify existing dependencies
- Read AndroidManifest.xml to check current permissions
- Read main.dart to understand app initialization flow
- Added flutter_local_notifications: ^17.0.0 to pubspec.yaml
- Created new file: download_notification_service.dart with singleton pattern
- Added POST_NOTIFICATIONS permission to AndroidManifest.xml for Android 13+
- Integrated DownloadNotificationService into DownloadManagerService at all lifecycle points:
  - init(): Initialize notification service + request permission
  - startDownload(): Show notification on download start
  - Progress update loop: Update notification with progress/speed/ETA
  - Download completed: Show completion notification (auto-dismisses after 5s)
  - Download failed (all failure paths): Show failure notification (auto-dismisses after 10s)
  - pauseDownload(): Cancel notification
  - removeTask(): Cancel notification
  - All DioException pause paths: Cancel notification
  - All DioException failure paths: Show failure notification
  - Generic catch failure paths: Show failure notification

Stage Summary:
- New file: lib/app/core/services/download_notification_service.dart — singleton service managing system notifications
- Modified: pubspec.yaml — added flutter_local_notifications: ^17.0.0
- Modified: lib/app/core/services/download_manager_service.dart — integrated notification service at 12 lifecycle points
- Modified: android/app/src/main/AndroidManifest.xml — added POST_NOTIFICATIONS permission
- Notification channel: 'downloads' / 'Downloads' with low importance (no sound during progress)
- Notifications show: movie title, quality, progress %, speed, ETA during download
- Ongoing (non-dismissible) notifications during active downloads
- Auto-dismissing completion (5s) and failure (10s) notifications
- Throttled notification updates (max 2x per second) to avoid performance impact
- Unique notification IDs per task via stable hash of task ID

---
Task ID: batch-import-task-1
Agent: main (Bro)
Task: Implement Phase 2 of Batch Import feature — BatchImportService + BatchImportPage + Admin Panel entry point + file_picker dependency

Work Log:
- Read origin/main latest commits (banner fix c164dec, selection handle fix 88cec91, etc.)
- Read firestore_content_service.dart addMovie() — has tmdbId+slug duplicate check, counter sync, idempotent updates
- Read MovieDetail model — full schema with seasons/episodes/casts/downloadLinks/watchLinks
- Read admin_panel_page.dart — TabBar with 6 tabs, FAB menu with Add Movie/Add Series
- Read tmdb_generator_page.dart — existing TMDB batch import pattern (sequential loop, progress bar)
- Read saf_storage_service.dart — folder-picker pattern (not file picker)
- Created feature/batch-import branch
- Added file_picker ^8.1.2 to pubspec.yaml (JSON file picking)
- Created lib/app/core/services/batch_import_service.dart
- Created lib/app/ui/screens/batch_import_page.dart
- Added entry point in admin_panel_page.dart FAB menu (3rd option)

Stage Summary:
- file_picker package added (cross-platform JSON file picking, no native MethodChannel needed)
- BatchImportService handles: parse → validate → preview classification → sequential import with progress callback
- Validation: title required, type must be 'movie'/'series', uses MovieDetail.fromMap as schema validator
- Preview: classifies items into new/update/skip (via tmdbId/slug duplicate check)
- Import: sequential addMovie() calls (reuses existing safety logic), per-item error capture
- BatchImportPage: 4-phase UI (pick file → validate → preview counts → import with progress bar + summary)
- Admin Panel FAB menu: 3rd option "Batch Import (JSON)" — opens new page
- Pushed to feature/batch-import branch — awaiting user build approval before merging to Main
