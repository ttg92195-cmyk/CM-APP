---
Task ID: 1
Agent: Main Agent
Task: SAF Folder Picker + Home Spacing + Detail Icon Sizing

Work Log:
- Created SafStorageService.dart with MethodChannel for Android SAF
- Updated MainActivity.kt with ACTION_OPEN_DOCUMENT_TREE handling, file save/exists/delete via ContentResolver
- Updated DownloadManagerService to integrate SAF folder selection and file copying after download
- Updated download_page.dart settings UI with "Choose Folder" button (SAF) replacing old folder icon
- Changed Storage Permission "Grant" from TextButton to green ElevatedButton
- Reduced Home Screen section spacing from 8px to 4px
- Reduced TrendingMovieComponent height from 250 to 230, padding from (16,8,16,12) to (16,4,16,8)
- Reduced Post Detail Back/Watchlist/Bookmark icons from 32x32 to 28x28, icon size from 18 to 16
- Reduced tab content padding in both MovieDetailScreen and SeriesDetailScreen
- Pushed to GitHub Main branch (commit dff3bfa)

Stage Summary:
- SAF folder picker: Users can now tap "Choose Folder" → system file picker opens → select folder → persistable permission granted → "Download location setup complete!" message
- Home screen more compact with less wasted space
- Post detail icons smaller and uniformly sized
- All changes pushed to GitHub
