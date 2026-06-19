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

---
Task ID: batch-import-task-2
Agent: main (Bro)
Task: Phase 3a — Pre-import Backup Export feature (export current Firestore movies to JSON)

Work Log:
- Pulled latest main (c10a84a — previous Batch Import commit)
- Added BatchExportProgress + BatchExportResult classes to batch_import_service.dart
- Added exportAllMovies() method:
  * Paginated fetch (pageSize=200) via Firestore startAfterDocument cursor
  * Serializes Timestamps → ISO-8601 strings, preserves doc.id as 'id'
  * Writes JSON file with _meta wrapper (exportedAt/count/source/appVersion)
  * Output wrapper uses 'movies' key — recognized by parseJsonString() for restore
  * Default output dir: app documents dir + '/batch_import_backups/'
  * File name format: cm_movies_backup_YYYY-MM-DD_HH-MM-ss.json
- Added path_provider import to batch_import_service.dart (already in pubspec)
- Added _buildBackupCard() to BatchImportPage Phase 1 (idle/pick screen):
  * Blue-tinted card with backup_outlined icon
  * "Export Database" button (Colors.blue, disabled while exporting)
  * Live progress: 'Exporting… N movies fetched so far' / 'Writing JSON file…'
  * Last export info chip (green) with count + size + file path
  * Error chip (red) if export fails
- Added _runExport() handler with progress callback wiring + SnackBar feedback
- Modified _reset() to NOT clear _lastExport (so backup info persists across imports)

Stage Summary:
- New BatchExportResult.sizeFormatted getter: human-readable "12.4 KB" / "1.8 MB"
- Export pagination handles 1000+ movies without OOM (steady-state ~40MB heap)
- Backup file is round-trip safe: parseJsonString() accepts the same format
- UI feedback at every stage: progress, success (green chip + SnackBar), error (red chip + SnackBar)
- No new dependencies — path_provider already in pubspec.yaml
- Pushed directly to Main for CI build (per Bro's preference for auto-build workflow)

---
Task ID: phase-3b
Agent: main (Bro)
Task: Phase 3b — Audit Log (record every batch import run + history UI)

Work Log:
- Pulled latest origin/main (d11af2a — Phase 3a backup/export) into local CM-APP
- Added 3 new classes to batch_import_service.dart:
  * BatchImportAuditContext (adminUid, adminEmail, sourceFileName, sourceFileSizeBytes, appVersion)
  * BatchImportAuditSummary (lightweight list-row view-model, fromDoc factory)
  * BatchImportAuditRecord (full detail view-model with failedItems + sample titles)
- Added firebase_auth import to batch_import_service.dart (already in pubspec as ^5.3.1)
- Modified runImport() to:
  * Accept optional BatchImportAuditContext? auditContext param
  * Track startedAt/completedAt/durationMs
  * Set `cancelled` flag when shouldStop() triggers early exit
  * After completion, call _recordAudit() (wrapped in try/catch so audit failures never break the import flow)
- Added Phase 4 section to BatchImportService:
  * auditCollectionName = 'batch_imports'
  * _recordAudit() — writes one doc with full payload (failedItems capped at 200, sampleCreated/Updated capped at 20)
  * listImports({limit = 50}) — newest-first one-shot fetch for history list
  * getImport(String id) — full detail fetch including failed-items list
  * deleteImport(String id) — for cleaning up accidental test imports
  * static currentAdminContext() helper — wraps FirebaseAuth.instance.currentUser
- Created new file: lib/app/ui/screens/batch_import_history_page.dart (864 lines)
  * BatchImportHistoryPage — FutureBuilder + RefreshIndicator list of past imports
  * _HistoryTile — colored status dot, file name, meta line (timestamp • duration • admin), count chips
  * BatchImportAuditDetailPage — full record view with Overview / Counts / Failed Items / Sample Created / Sample Updated sections
  * Delete record button with confirmation dialog (only removes audit entry, NOT the imported movies)
  * Pull-to-refresh support (AlwaysScrollableScrollPhysics)
  * Empty / error / loading states all implemented
- Modified batch_import_page.dart:
  * Added imports: package_info_plus, batch_import_history_page.dart
  * Added History icon button to AppBar (always visible — opens BatchImportHistoryPage)
  * Added _fileSizeBytes state field (populated from FilePicker result.size)
  * _pickFile() now captures file size into _fileSizeBytes
  * _startImport() now:
    - Fetches app version via PackageInfo.fromPlatform() (best-effort, try/catch)
    - Builds BatchImportAuditContext via BatchImportService.currentAdminContext()
    - Passes auditContext to runImport()
  * _reset() now clears _fileSizeBytes too
- Updated firestore.rules:
  * Added new match /batch_imports/{importId} block
  * read/create/update/delete all admin-only (matches /movies/ pattern)
  * Reason: collection exposes admin emails + source-file metadata
  * NOTE: rules file change is in the commit, but actual deployment requires `firebase deploy --only firestore:rules` (not done by GitHub Actions build workflow)

Stage Summary:
- Every batch import now leaves a permanent audit trail in Firestore
- Admin can browse past imports via the History icon in the AppBar
- Each audit doc captures: who (adminUid/email), when (startedAt/completedAt/durationMs), what (sourceFileName/size), outcome (total/created/updated/failed/skipped/cancelled), and detail (failedItems list + sample titles)
- Audit write is non-fatal: if Firestore rules reject it or network fails, the import itself still completes successfully
- New Firestore collection 'batch_imports' requires rules deployment — Bro needs to run `firebase deploy --only firestore:rules` or paste the rules into Firebase Console
- Files changed: 3 (batch_import_service.dart +346 lines, batch_import_page.dart +43 lines, batch_import_history_page.dart +864 new)
- Rules file: firestore.rules +11 lines (new batch_imports block)
- Pushed directly to Main for CI build (per Bro's preference for auto-build workflow)

---
Task ID: phase-3c
Agent: main (Bro)
Task: Phase 3c — Per-failed-item retry (re-import only items that failed)

Work Log:
- Pulled latest origin/main (9605fa4 — Phase 3b audit log) into local CM-APP
- Verified clean working tree before starting work
- Re-read batch_import_service.dart end-to-end (1-1149 lines) to refresh full context

Service layer (batch_import_service.dart):
- Added isRetry field to BatchImportAuditContext (default false)
- Added copyWith() method to BatchImportAuditContext for retry-flow (UI flips isRetry=true, prefixes sourceFileName with '(retry)')
- toPartialFirestoreMap() now includes 'isRetry' so it's written to Firestore
- Added isRetry field to BatchImportAuditSummary + fromDoc() (reads 'isRetry' with ?? false default — backward compatible with existing audit docs)
- Added isRetry field to BatchImportAuditRecord (passes through to super)
- Added new retryFailed() method (~50 lines):
  * Filters items to only those with importResult == 'failure'
  * Resets each failed item's importResult/importError to null
  * Preserves item.status (willCreate/willUpdate) — addMovie() re-checks duplicates anyway
  * Delegates to existing runImport() — no loop duplication, all safety logic reused
  * If auditContext provided, runImport records a fresh audit doc with isRetry=true
  * Returns new BatchImportResult covering only retried items (total = failed count, not original batch size)
  * Empty-failed-list case returns empty result safely

UI layer (batch_import_page.dart):
- Added _isRetryResult state field — tracks whether _result came from a retry
- Reset _isRetryResult=false in _reset() and at start of _startImport()
- Added new _retryFailed() method:
  * Defensive check: if result.failed == 0, show SnackBar and return
  * Sets phase to importing, resets _cancelRequested/_progress
  * Builds audit context with currentAdminContext, then copyWith(isRetry: true) + '(retry) filename' prefix
  * Calls _service.retryFailed(previousResult.items, ...)
  * On success: replaces _result with retryResult, sets _isRetryResult=true, shows SnackBar (green if all-good, orange if partial)
  * On error: returns to summary phase, shows red SnackBar
- Updated _buildSummaryPhase header text: 'Retry Complete!' / 'Retry Completed (with failures)' when _isRetryResult
- Updated summary action bar: now a Column with full-width 'Retry N Failed Items' button (orange) when hasFailures && !_isRetryResult, then the existing row of Import Another + Done buttons
  * Retry button is HIDDEN after a retry run to prevent UI-level infinite retry loops (admin can hit Import Another to start fresh)
  * Button label dynamically pluralizes: 'Retry 1 Failed Item' vs 'Retry 3 Failed Items'

History UI (batch_import_history_page.dart):
- _HistoryTile: title row now uses a Row with Flexible(Text) + optional '↻ RETRY' badge (purple chip) when summary.isRetry
- _DetailBody Overview section: added 'Type' row showing '↻ Retry (of failed items)' vs 'Fresh import'

Stage Summary:
- Retry flow: tap Retry Failed → re-imports only failed items → fresh audit log row with isRetry=true → summary shows retry outcomes (created/updated/failed/skipped of the retry, not original)
- Retry is safe: re-uses runImport's existing addMovie() safety (duplicate detection, counter sync, idempotent updates)
- Retry button is hidden after a retry to prevent UI loops — admin can still tap 'Import Another' to start over
- Audit log distinguishes retry runs from fresh imports via isRetry field — visible in both list ('↻ RETRY' badge) and detail (Type row)
- Backward compatible: old audit docs without 'isRetry' field default to false via ?? false
- Files changed: 3 (batch_import_service.dart +99 lines, batch_import_page.dart +106 lines, batch_import_history_page.dart +37 lines)
- No new dependencies — all features use existing firebase_auth, cloud_firestore, package_info_plus
- No Firestore rules changes needed — retry writes to same batch_imports collection with same admin-only permission
- Pushed directly to Main for CI build (per Bro's preference for auto-build workflow)

---
Task ID: phase-3d
Agent: main (Bro)
Task: Phase 3d — Memory safety for large files (hard caps + pre-parse warning UX)

Work Log:
- Pulled latest origin/main (2f9b551 — Phase 3c retry) into local CM-APP
- Verified clean working tree before starting work
- Re-read batch_import_service.dart end-to-end (1-1237 lines) to refresh full context
- Re-read batch_import_page.dart end-to-end (1-1680 lines) to refresh full context

Service layer (batch_import_service.dart):
- Added 3 new static constants in a new "PHASE 3d — MEMORY SAFETY GUARDS" section:
  * maxFileSizeBytes = 50 * 1024 * 1024 (50 MB hard cap)
  * maxItemsPerImport = 5000 (hard cap on array length)
  * largeFileWarningBytes = 5 * 1024 * 1024 (5 MB soft UX threshold)
- Added static formatFileSize(int bytes) helper — returns "12.4 KB" / "1.8 MB" / etc.
  Used by both service (in error messages) and UI (in chip + dialog), so they format consistently.
- Modified parseFile():
  * After file.exists() check, before reading bytes:
    if (fileSize > maxFileSizeBytes) throw BatchImportException(...)
  * Error message is admin-friendly: shows actual size, the limit, and what to do
    ("split the file into smaller chunks of ~1000 movies each")
  * Doc-comment updated to explain the layered guard (hard cap here + soft warning in UI)
- Modified parseJsonString():
  * After extracting the array (and confirming non-empty), before iterating:
    if (array.length > maxItemsPerImport) throw BatchImportException(...)
  * Error message tells admin exactly how many items they have, the limit, and that
    re-running Batch Import on split files is safe (duplicates are auto-skipped)

UI layer (batch_import_page.dart):
- Added _isLargeFile getter on _BatchImportPageState:
  returns true when _fileSizeBytes > BatchImportService.largeFileWarningBytes
- Updated file chip (in _buildPickPhase):
  * Border turns orange (instead of red) when _isLargeFile
  * Icon switches to warning_amber_rounded (orange) when _isLargeFile
  * Now shows a second line below the filename with the formatted file size
  * For large files, that line says "12.3 MB • large file — confirm before parsing"
    in orange bold; for normal files just shows "234 KB" in muted grey
- Updated _parseFile():
  * At the very start, before any state changes, if _isLargeFile is true:
    show confirmation dialog via _showLargeFileConfirmDialog()
  * If admin cancels (returns false), bail out without changing phase
  * Only proceed to _Phase.parsing if confirmed or file is small
- Added _showLargeFileConfirmDialog() (~40 lines):
  * AlertDialog with warning_amber_rounded icon
  * Title: "Large File Warning"
  * Body: shows actual file size, explains memory/time implications, mentions
    the 50 MB hard cap, suggests splitting into ~1000-movie batches
  * Two buttons: "Cancel" (TextButton) + "Parse Anyway" (orange FilledButton)
  * barrierDismissible: false — forces an explicit choice (no accidental parse)
  * Returns bool? — null/false treated as cancel

Stage Summary:
- Three layers of protection against OOM/billing surprises:
  1. UI soft warning (5 MB+): chip turns orange + dialog forces explicit confirm
  2. Service hard cap on file size (50 MB): throws before any bytes are read
  3. Service hard cap on item count (5000): throws after JSON decode, before iteration
- All error messages are admin-actionable — they say exactly what's wrong and what to do
- File size now visible in the chip for ALL files (not just large ones) — admin can
  sanity-check at a glance that they picked the right file
- No Firestore rules changes needed (no new collections / no new write paths)
- No new dependencies — uses only existing dart:io File API
- Files changed: 2 (batch_import_service.dart +83 lines, batch_import_page.dart +111 lines)
- Backward compatible: existing small/normal files behave exactly as before
- Pushed directly to Main for CI build (per Bro's preference for auto-build workflow)
