# Task: Add Download Progress Notifications (In-App)

## Summary
Added in-app notification banners that display real-time download progress when users are downloading videos.

## Files Created

### 1. `/home/z/my-project/CM-APP/lib/app/ui/components/download_notification_banner.dart`
- **DownloadNotificationBanner**: Full-featured floating banner for the download page
  - Shows when downloads are actively running (status == downloading)
  - Single download: displays movie title, quality badge, downloaded size, speed, ETA, progress %
  - Multiple downloads: shows "X downloads in progress" with aggregate progress, total speed, and longest ETA
  - Red accent gradient (#E50914) matching app theme
  - Animated progress bar at the bottom of the banner
  - Pulsing download icon indicator
  - Dismissible by swiping (horizontal Dismissible)
  - Auto-reappears when new downloads start after being dismissed
  - Connects to existing `DownloadManagerService` via `ListenableBuilder` - no separate tracking system

- **DownloadMiniIndicator**: Compact floating indicator for the home page
  - Smaller footprint for less intrusive notification
  - Circular progress ring around download icon
  - Shows title, percentage, and speed
  - Tappable - navigates to Download page (with permission check on Android)
  - Uses same `DownloadManagerService` singleton

## Files Modified

### 2. `/home/z/my-project/CM-APP/lib/app/ui/screens/download_page.dart`
- Added import for `download_notification_banner.dart`
- Added `DownloadNotificationBanner` widget at the top of the Scaffold body Column
- Positioned above the permission banner and download toggle for maximum visibility

### 3. `/home/z/my-project/CM-APP/lib/app/ui/home/home_page.dart`
- Added import for `download_notification_banner.dart`
- Changed Scaffold body from `IndexedStack` to `Stack` wrapping `IndexedStack`
- Added `Positioned` `DownloadMiniIndicator` at the bottom of the Stack
- Mini indicator floats above the bottom navigation bar
- On tap: checks Android runtime permission then navigates to DownloadPage
- Users see download progress even when not on the download page

## Key Design Decisions
- Reused existing `DownloadManagerService` ChangeNotifier - no new tracking system
- Filtered for `DownloadStatus.downloading` only (paused downloads don't show in banner)
- Aggregate progress for multiple downloads uses average of individual progresses
- Aggregate speed uses sum of all download speeds
- ETA for multiple downloads uses the longest remaining ETA
- Dismissible banner auto-reappears if new downloads start
- Mini indicator is not dismissible (always shows when downloads active)
