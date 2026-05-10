import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import inch, cm
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    KeepTogether, HRFlowable
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import registerFontFamily

# ── Register Fonts ──
pdfmetrics.registerFont(TTFont('NotoSansSC', '/usr/share/fonts/truetype/noto-serif-sc/NotoSerifSC-Regular.ttf'))
pdfmetrics.registerFont(TTFont('NotoSerifSC', '/usr/share/fonts/truetype/noto-serif-sc/NotoSerifSC-Regular.ttf'))
pdfmetrics.registerFont(TTFont('NotoSerifSC-Bold', '/usr/share/fonts/truetype/noto-serif-sc/NotoSerifSC-Bold.ttf'))
pdfmetrics.registerFont(TTFont('SarasaMonoSC', '/usr/share/fonts/truetype/chinese/SarasaMonoSC-Regular.ttf'))
pdfmetrics.registerFont(TTFont('DejaVuSans', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'))
registerFontFamily('NotoSerifSC', normal='NotoSerifSC', bold='NotoSerifSC-Bold')
registerFontFamily('NotoSansSC', normal='NotoSansSC', bold='NotoSansSC')
registerFontFamily('SarasaMonoSC', normal='SarasaMonoSC', bold='SarasaMonoSC')
registerFontFamily('DejaVuSans', normal='DejaVuSans', bold='DejaVuSans')

# ── Color Palette ──
ACCENT       = colors.HexColor('#5030af')
TEXT_PRIMARY  = colors.HexColor('#1b1a19')
TEXT_MUTED    = colors.HexColor('#858178')
BG_SURFACE   = colors.HexColor('#e1ded8')
BG_PAGE      = colors.HexColor('#f0efec')
TABLE_HEADER_COLOR = ACCENT
TABLE_HEADER_TEXT  = colors.white
TABLE_ROW_EVEN     = colors.white
TABLE_ROW_ODD      = BG_SURFACE

# Severity colors
CRITICAL_COLOR = colors.HexColor('#dc2626')
HIGH_COLOR     = colors.HexColor('#ea580c')
MEDIUM_COLOR   = colors.HexColor('#ca8a04')
LOW_COLOR      = colors.HexColor('#16a34a')

# ── Styles ──
page_width = A4[0]
left_margin = 1.0 * inch
right_margin = 1.0 * inch
available_width = page_width - left_margin - right_margin

title_style = ParagraphStyle(
    name='Title', fontName='NotoSansSC', fontSize=28, leading=36,
    textColor=ACCENT, alignment=TA_LEFT, spaceAfter=6
)
subtitle_style = ParagraphStyle(
    name='Subtitle', fontName='NotoSansSC', fontSize=14, leading=20,
    textColor=TEXT_MUTED, alignment=TA_LEFT, spaceAfter=18
)
h1_style = ParagraphStyle(
    name='H1', fontName='NotoSansSC', fontSize=20, leading=28,
    textColor=ACCENT, spaceBefore=18, spaceAfter=10
)
h2_style = ParagraphStyle(
    name='H2', fontName='NotoSansSC', fontSize=15, leading=22,
    textColor=TEXT_PRIMARY, spaceBefore=14, spaceAfter=8
)
h3_style = ParagraphStyle(
    name='H3', fontName='NotoSerifSC', fontSize=12, leading=18,
    textColor=TEXT_PRIMARY, spaceBefore=10, spaceAfter=6
)
body_style = ParagraphStyle(
    name='Body', fontName='NotoSerifSC', fontSize=10.5, leading=18,
    textColor=TEXT_PRIMARY, alignment=TA_LEFT, wordWrap='CJK',
    spaceAfter=6
)
code_style = ParagraphStyle(
    name='Code', fontName='DejaVuSans', fontSize=9, leading=14,
    textColor=colors.HexColor('#334155'), backColor=colors.HexColor('#f1f5f9'),
    spaceAfter=6, leftIndent=12, rightIndent=12,
    borderPadding=(4, 4, 4, 4)
)
muted_style = ParagraphStyle(
    name='Muted', fontName='NotoSerifSC', fontSize=9, leading=14,
    textColor=TEXT_MUTED, spaceAfter=4
)
bullet_style = ParagraphStyle(
    name='Bullet', fontName='NotoSerifSC', fontSize=10.5, leading=18,
    textColor=TEXT_PRIMARY, alignment=TA_LEFT, wordWrap='CJK',
    spaceAfter=4, leftIndent=24, bulletIndent=12
)
table_header_style = ParagraphStyle(
    name='TH', fontName='NotoSerifSC', fontSize=10, leading=14,
    textColor=TABLE_HEADER_TEXT, alignment=TA_CENTER
)
table_cell_style = ParagraphStyle(
    name='TC', fontName='NotoSerifSC', fontSize=9.5, leading=14,
    textColor=TEXT_PRIMARY, alignment=TA_LEFT, wordWrap='CJK'
)
table_cell_center = ParagraphStyle(
    name='TCC', fontName='NotoSerifSC', fontSize=9.5, leading=14,
    textColor=TEXT_PRIMARY, alignment=TA_CENTER
)

# ── Helper Functions ──
def make_severity_badge(severity):
    color_map = {'CRITICAL': CRITICAL_COLOR, 'HIGH': HIGH_COLOR, 'MEDIUM': MEDIUM_COLOR, 'LOW': LOW_COLOR}
    c = color_map.get(severity, TEXT_MUTED)
    style = ParagraphStyle(name=f'Badge_{severity}', fontName='NotoSerifSC', fontSize=8.5, leading=12,
                           textColor=colors.white, alignment=TA_CENTER)
    return Paragraph(f'<b>{severity}</b>', style)

def issue_table(issues_data):
    """Create a formatted issue table. issues_data: list of [severity, title, file, description]"""
    header = [
        Paragraph('<b>Severity</b>', table_header_style),
        Paragraph('<b>Issue</b>', table_header_style),
        Paragraph('<b>File</b>', table_header_style),
        Paragraph('<b>Description</b>', table_header_style),
    ]
    data = [header]
    for sev, title, file, desc in issues_data:
        data.append([
            make_severity_badge(sev),
            Paragraph(f'<b>{title}</b>', table_cell_style),
            Paragraph(file, table_cell_style),
            Paragraph(desc, table_cell_style),
        ])
    col_widths = [0.10 * available_width, 0.20 * available_width, 0.25 * available_width, 0.45 * available_width]
    t = Table(data, colWidths=col_widths, hAlign='CENTER')
    style_cmds = [
        ('BACKGROUND', (0, 0), (-1, 0), TABLE_HEADER_COLOR),
        ('TEXTCOLOR', (0, 0), (-1, 0), TABLE_HEADER_TEXT),
        ('GRID', (0, 0), (-1, -1), 0.5, TEXT_MUTED),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]
    # Severity badge backgrounds
    sev_colors = {'CRITICAL': CRITICAL_COLOR, 'HIGH': HIGH_COLOR, 'MEDIUM': MEDIUM_COLOR, 'LOW': LOW_COLOR}
    for i, row in enumerate(data[1:], 1):
        sev = issues_data[i-1][0]
        style_cmds.append(('BACKGROUND', (0, i), (0, i), sev_colors.get(sev, TEXT_MUTED)))
        style_cmds.append(('BACKGROUND', (1, i), (-1, i), TABLE_ROW_EVEN if i % 2 == 1 else TABLE_ROW_ODD))
    t.setStyle(TableStyle(style_cmds))
    return t

# ── Build Document ──
output_path = '/home/z/my-project/download/CM-APP_Code_Review_Report.pdf'
doc = SimpleDocTemplate(
    output_path, pagesize=A4,
    leftMargin=left_margin, rightMargin=right_margin,
    topMargin=1.0*inch, bottomMargin=1.0*inch
)

story = []

# ══════════════════════════════════════
# COVER / TITLE SECTION
# ══════════════════════════════════════
story.append(Spacer(1, 40))
story.append(Paragraph('<b>CM-APP Code Review Report</b>', title_style))
story.append(HRFlowable(width='100%', thickness=2, color=ACCENT, spaceAfter=12))
story.append(Paragraph('GitHub: ttg92195-cmyk/CM-APP | Branch: main | Flutter Movie App (KMM)', subtitle_style))
story.append(Spacer(1, 8))

# Summary metrics table
summary_data = [
    [Paragraph('<b>Metric</b>', table_header_style), Paragraph('<b>Value</b>', table_header_style)],
    [Paragraph('Project', table_cell_style), Paragraph('CM Movies (KMM) - Flutter Movie/Series App', table_cell_style)],
    [Paragraph('Framework', table_cell_style), Paragraph('Flutter 3.x + Dart', table_cell_style)],
    [Paragraph('Backend', table_cell_style), Paragraph('Firebase (Auth + Firestore)', table_cell_style)],
    [Paragraph('Total Dart Files', table_cell_style), Paragraph('30+', table_cell_style)],
    [Paragraph('CRITICAL Issues', table_cell_style), Paragraph('5', ParagraphStyle(name='crit', fontName='NotoSerifSC', fontSize=9.5, leading=14, textColor=CRITICAL_COLOR))],
    [Paragraph('HIGH Issues', table_cell_style), Paragraph('7', ParagraphStyle(name='hi', fontName='NotoSerifSC', fontSize=9.5, leading=14, textColor=HIGH_COLOR))],
    [Paragraph('MEDIUM Issues', table_cell_style), Paragraph('10', ParagraphStyle(name='med', fontName='NotoSerifSC', fontSize=9.5, leading=14, textColor=MEDIUM_COLOR))],
    [Paragraph('LOW Issues', table_cell_style), Paragraph('10', ParagraphStyle(name='lo', fontName='NotoSerifSC', fontSize=9.5, leading=14, textColor=LOW_COLOR))],
    [Paragraph('Review Date', table_cell_style), Paragraph('2026-05-10', table_cell_style)],
]
summary_table = Table(summary_data, colWidths=[0.30*available_width, 0.70*available_width], hAlign='CENTER')
summary_table.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), TABLE_HEADER_COLOR),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
    ('GRID', (0, 0), (-1, -1), 0.5, TEXT_MUTED),
    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ('LEFTPADDING', (0, 0), (-1, -1), 8),
    ('RIGHTPADDING', (0, 0), (-1, -1), 8),
    ('TOPPADDING', (0, 0), (-1, -1), 5),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ('BACKGROUND', (0, 1), (0, -1), BG_SURFACE),
] + [('BACKGROUND', (1, i), (1, i), TABLE_ROW_EVEN if i%2==1 else TABLE_ROW_ODD) for i in range(1, 10)]))
story.append(summary_table)
story.append(Spacer(1, 24))

# ══════════════════════════════════════
# 1. CRITICAL ISSUES
# ══════════════════════════════════════
story.append(Paragraph('<b>1. CRITICAL - Security Issues</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=CRITICAL_COLOR, spaceAfter=8))

story.append(Paragraph('These issues pose immediate security risks and should be addressed before any production deployment. Exposed credentials, hardcoded admin emails, and missing security rules can lead to unauthorized access, data breaches, and abuse of your Firebase backend.', body_style))
story.append(Spacer(1, 8))

critical_issues = [
    ['CRITICAL', 'GitHub Token Exposed', 'Chat/N/A',
     'The GitHub Personal Access Token (REDACTED_TOKEN) was shared in plaintext. This token must be revoked immediately via GitHub Settings > Developer Settings > Personal Access Tokens. Any leaked token can be used to access private repositories, modify code, or create malicious commits.'],
    ['CRITICAL', 'Firebase API Key Exposed', 'firebase_options.dart, google-services.json',
     'Firebase API key (AIzaSyCYTCj8UBoaEj-LH_R3NjrW5S5GJC87oMo) and project configuration are committed to the repository. While Firebase API keys are designed to be somewhat public, Firestore Security Rules must be properly configured to prevent unauthorized read/write access. If rules are set to allow all, anyone can read or delete your entire database.'],
    ['CRITICAL', 'Admin Email Hardcoded', 'app_config.dart:36',
     'Admin email "guyg20985@gmail.com" is hardcoded in _adminEmailMap. This is a severe security vulnerability because anyone reading the source code (which is public on GitHub) can identify the admin account and attempt targeted attacks. Use Firebase Custom Claims or a Firestore "admins" collection instead.'],
    ['CRITICAL', 'No .gitignore File', 'Project Root',
     'The repository has no .gitignore file. Sensitive files like google-services.json, firebase_options.dart, and build artifacts are committed. A proper Flutter .gitignore should exclude android/app/google-services.json, build/, .dart_tool/, and environment-specific config files.'],
    ['CRITICAL', 'No Firestore Security Rules', 'N/A (Missing)',
     'No firestore.rules file exists in the repository. Without explicit rules, Firestore defaults to deny-all (if in production mode) or allow-all (if in test mode). If test mode, any client can read/write/delete all data including user profiles, bookmarks, and admin content.'],
]
story.append(issue_table(critical_issues))
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 2. HIGH ISSUES
# ══════════════════════════════════════
story.append(Paragraph('<b>2. HIGH - Architecture and Design Issues</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=HIGH_COLOR, spaceAfter=8))

story.append(Paragraph('These issues affect the maintainability, scalability, and reliability of the application. They represent fundamental design problems that will become increasingly difficult to fix as the codebase grows. Addressing them early will save significant refactoring effort later.', body_style))
story.append(Spacer(1, 8))

high_issues = [
    ['HIGH', 'Service Instantiation Anti-Pattern', 'Multiple Screens',
     'Each screen creates new service instances (FirestoreContentService(), BookmarkService(), etc.) instead of using dependency injection or singletons. This wastes resources, prevents shared state, and makes testing difficult. Use a service locator (get_it) or Provider-based injection to share instances across the app.'],
    ['HIGH', 'No Global Error Handling', 'Entire App',
     'Errors are silently caught with catch (e) { debugPrint(...) } throughout the codebase. There is no global error boundary, no user-facing error messages in many places, and no crash reporting. Implement Flutter ErrorWidget, Zone error handling, and integrate Firebase Crashlytics for production error tracking.'],
    ['HIGH', 'Massive Code Duplication', 'bookmark_service.dart, watchlist_service.dart',
     'BookmarkService and WatchlistService share approximately 90% identical code (local/cloud storage, Firestore operations, merge logic). This violates DRY principles. Create a generic BaseCollectionService<T> that handles CRUD, sync, and local fallback, then extend it for bookmarks and watchlist.'],
    ['HIGH', 'No Reactive State for Data', 'All Screens',
     'Provider is only used for AppConfig. Movie lists, bookmarks, and watchlist data are fetched independently on each screen with no shared reactive state. When a user bookmarks a movie on one screen, other screens do not update. Implement a proper state management solution (Riverpod, BLoC, or Provider with ChangeNotifier for data models).'],
    ['HIGH', 'Dead Code: ApiService', 'api_service.dart',
     'ApiService references URL constants from constants.dart, but that file is now empty ("API URLs removed - now using Firebase Firestore"). All API URL references (apiMovieTrendingUrl, apiSearchUrl, etc.) will resolve to null/empty, making the entire service non-functional. Either remove this dead code or document it as deprecated.'],
    ['HIGH', 'Download Manager Platform-Specific', 'download_manager_service.dart',
     'Hardcoded path /storage/emulated/0/Download/CM_Movies/ only works on Android. No iOS support using path_provider. No Android 10+ scoped storage permission handling (WRITE_EXTERNAL_STORAGE is deprecated). No check for storage availability or permission before download. Use path_provider getApplicationDocumentsDirectory() or getExternalStorageDirectory().'],
    ['HIGH', 'No Admin Authorization on Backend', 'admin_panel_page.dart',
     'Admin CRUD operations (add/edit/delete movies, genres, tags) are performed directly from the client with no backend validation. Any user who discovers the admin panel route can modify content. Firestore Security Rules should verify isAdmin custom claims before allowing write operations.'],
]
story.append(issue_table(high_issues))
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 3. MEDIUM ISSUES
# ══════════════════════════════════════
story.append(Paragraph('<b>3. MEDIUM - Code Quality Issues</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=MEDIUM_COLOR, spaceAfter=8))

story.append(Paragraph('These issues affect code maintainability and can lead to bugs, performance problems, or inconsistent behavior. While not immediately dangerous, they should be addressed to improve the overall health of the codebase and prevent future regressions.', body_style))
story.append(Spacer(1, 8))

medium_issues = [
    ['MEDIUM', 'Duplicated DateTime Parsing', 'movie.dart, movie_detail.dart',
     '_parseDateTime and _parseDateTimeDetail are identical functions in two different model files. Extract to a shared utility file (e.g., utils/date_parser.dart) to avoid maintenance burden and potential divergence.'],
    ['MEDIUM', 'Inefficient Client-Side Search', 'firestore_content_service.dart',
     'searchMovies() fetches up to 500 documents from Firestore and filters client-side. This approach is extremely expensive on Firestore reads (each read counts toward billing quota) and will not scale. Consider using Algolia, Typesense, or Firebase Extensions for full-text search. At minimum, implement debouncing and caching.'],
    ['MEDIUM', 'Excessive Fallback Patterns', 'firestore_content_service.dart',
     'Every Firestore query has try/catch with a fallback query without orderBy. This masks the real problem: missing composite indexes. Instead of working around missing indexes, create the required Firestore composite indexes using firestore.indexes.json and the Firebase Console. The fallback pattern doubles your Firestore read costs.'],
    ['MEDIUM', 'No Pagination in Admin Panel', 'admin_panel_page.dart',
     'getAllPosts(limit: 100) loads up to 100 items at once with no infinite scroll or load-more mechanism. As content grows, this will become slow and memory-intensive. Implement cursor-based pagination similar to the user-facing screens.'],
    ['MEDIUM', 'Movie ID Inconsistency', 'movie.dart',
     'Movie.fromMap uses docId parameter for Firestore documents, but toMap() includes the id field separately. When saving bookmarks locally via SharedPreferences, the id from toMap() is used. If docId and map["id"] differ, bookmark/watchlist lookups will fail. Ensure consistent ID handling throughout the data flow.'],
    ['MEDIUM', 'No URL Validation', 'add_movie_page.dart, edit_movie_page.dart',
     'Poster URL, Backdrop URL, and download link URL fields accept any string without validation. Invalid URLs will cause image loading failures and broken download links. Add URL format validation and optionally a URL preview feature.'],
    ['MEDIUM', 'withOpacity Performance Issue', 'Multiple Files',
     'Color(0xFFE50914).withOpacity(0.15) is called extensively in build methods. Each call creates a new Color object on every widget rebuild, causing unnecessary garbage collection. Pre-compute these colors as static constants or use Color.fromARGB() for better performance.'],
    ['MEDIUM', 'SharedPreferences for Large Data', 'download_manager_service.dart, bookmark_service.dart',
     'Storing serialized JSON lists (bookmarks, downloads) in SharedPreferences has size limits and performance issues. For download tasks especially, as the list grows, serialization/deserialization becomes slow. Consider using Hive, Isar, or sqflite for structured local storage.'],
    ['MEDIUM', 'Missing Input Sanitization', 'add_movie_page.dart, admin_panel_page.dart',
     'Admin forms accept raw text for genre names, tags, movie titles, etc. without sanitization. Special characters or extremely long strings could break Firestore operations or UI rendering. Add input length limits and character filtering.'],
    ['MEDIUM', 'No Loading States for Background Ops', 'Multiple Screens',
     'Some async operations (bookmark toggle, watchlist add) do not show loading indicators. Users may tap multiple times, causing duplicate operations. Add loading states and disable buttons during async operations.'],
]
story.append(issue_table(medium_issues))
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 4. LOW ISSUES
# ══════════════════════════════════════
story.append(Paragraph('<b>4. LOW - Improvements and Best Practices</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=LOW_COLOR, spaceAfter=8))

story.append(Paragraph('These are recommended improvements that follow Flutter and Dart best practices. While not causing immediate problems, implementing them will improve code quality, developer experience, and long-term maintainability of the project.', body_style))
story.append(Spacer(1, 8))

low_issues = [
    ['LOW', 'No Test Files', 'Entire Project',
     'The project has zero test files. No unit tests, widget tests, or integration tests exist. This makes refactoring risky and regressions likely. At minimum, add unit tests for services (BookmarkService, FirestoreContentService) and widget tests for key screens.'],
    ['LOW', 'No CI/CD Pipeline', 'Project Root',
     'No GitHub Actions or other CI/CD configuration. Automated testing, linting, and build verification are missing. Add a basic GitHub Actions workflow for flutter test, flutter analyze, and flutter build.'],
    ['LOW', 'Hardcoded UI Strings', 'Multiple Screens',
     'Many UI strings in admin screens ("Admin Panel", "Add Movie", "Delete Confirmation") are hardcoded in English instead of using the translation system. This creates inconsistency where some screens support bilingual (Myanmar/English) and others do not.'],
    ['LOW', 'No Analytics/Crash Reporting', 'Entire App',
     'No Firebase Analytics, Crashlytics, or any usage tracking. You have no visibility into how users interact with the app or what errors they encounter. Integrate Firebase Analytics for user behavior and Crashlytics for crash reporting.'],
    ['LOW', 'Missing iOS Support', 'firebase_options.dart',
     'DefaultFirebaseOptions throws UnsupportedError for iOS. The app cannot run on iOS devices. Add iOS Firebase configuration if cross-platform support is desired.'],
    ['LOW', 'Theme Color Hardcoded', 'Multiple Files',
     'Color(0xFFE50914) (Netflix red) is repeated dozens of times across files instead of referencing the theme. If the brand color changes, every file needs updating. Define it once in the theme or as a constant.'],
    ['LOW', 'No README.md', 'Project Root',
     'No project documentation exists. A README should include: setup instructions, Firebase configuration steps, environment variables needed, and build/run commands. This is especially important for a project with Firebase dependencies.'],
    ['LOW', 'firestore.indexes.json May Be Incomplete', 'firestore.indexes.json',
     'The file exists but likely does not cover all the composite indexes needed by the queries with fallback patterns. Every fallback query indicates a missing index. Review all Firestore queries and add the required composite indexes.'],
    ['LOW', 'No Deep Linking', 'Entire App',
     'No support for sharing movie links or opening the app from a URL. This is a common feature for movie apps and would improve user engagement. Consider implementing Firebase Dynamic Links or universal links.'],
    ['LOW', 'Edit Page Always Clears Backdrop', 'edit_movie_page.dart:121',
     'When editing a movie, backdrop is always set to null (line 121: "backdrop": null). This means every edit operation removes the backdrop image. The backdrop URL should be loaded from the existing data and preserved unless explicitly cleared by the user.'],
]
story.append(issue_table(low_issues))
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 5. PROJECT STRUCTURE OVERVIEW
# ══════════════════════════════════════
story.append(Paragraph('<b>5. Project Structure Overview</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=ACCENT, spaceAfter=8))

story.append(Paragraph('The project follows a reasonable Flutter project structure with separation of concerns between models, services, and UI screens. However, there are some organizational improvements that could enhance maintainability and scalability as the codebase grows.', body_style))
story.append(Spacer(1, 8))

structure_data = [
    [Paragraph('<b>Directory</b>', table_header_style), Paragraph('<b>Purpose</b>', table_header_style), Paragraph('<b>Notes</b>', table_header_style)],
    [Paragraph('lib/main.dart', table_cell_style), Paragraph('App entry point, theme configuration', table_cell_style), Paragraph('Theme definitions are very long (300 lines). Consider extracting to a separate theme file.', table_cell_style)],
    [Paragraph('lib/app/core/models/', table_cell_style), Paragraph('Data models (Movie, MovieDetail, TagAndGenres, MovieYear)', table_cell_style), Paragraph('Models are well-structured. MovieYear may be unused after Firestore migration.', table_cell_style)],
    [Paragraph('lib/app/core/services/', table_cell_style), Paragraph('Business logic services (7 services)', table_cell_style), Paragraph('High duplication between BookmarkService and WatchlistService. ApiService is dead code.', table_cell_style)],
    [Paragraph('lib/app/ui/screens/', table_cell_style), Paragraph('Page-level widgets (16 screens)', table_cell_style), Paragraph('Some screens are very large (edit_movie_page.dart = 787 lines). Consider breaking into smaller widgets.', table_cell_style)],
    [Paragraph('lib/app/ui/home/', table_cell_style), Paragraph('Home tab components', table_cell_style), Paragraph('Good separation of home screen from tab navigation.', table_cell_style)],
    [Paragraph('lib/app/ui/components/', table_cell_style), Paragraph('Reusable UI components', table_cell_style), Paragraph('Only 3 components. Many reusable patterns (section titles, multi-select chips) are duplicated across screens.', table_cell_style)],
    [Paragraph('lib/more_libs/setting/', table_cell_style), Paragraph('App configuration and state', table_cell_style), Paragraph('AppConfig handles too many responsibilities: auth, theme, language, translations. Should be split.', table_cell_style)],
    [Paragraph('android/', table_cell_style), Paragraph('Android native configuration', table_cell_style), Paragraph('google-services.json should not be in version control. Use environment-based configuration.', table_cell_style)],
]
structure_table = Table(structure_data, colWidths=[0.25*available_width, 0.35*available_width, 0.40*available_width], hAlign='CENTER')
structure_table.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), TABLE_HEADER_COLOR),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
    ('GRID', (0, 0), (-1, -1), 0.5, TEXT_MUTED),
    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ('LEFTPADDING', (0, 0), (-1, -1), 6),
    ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ('TOPPADDING', (0, 0), (-1, -1), 5),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
] + [('BACKGROUND', (0, i), (-1, i), TABLE_ROW_EVEN if i%2==1 else TABLE_ROW_ODD) for i in range(1, 9)]))
story.append(structure_table)
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 6. PRIORITY RECOMMENDATIONS
# ══════════════════════════════════════
story.append(Paragraph('<b>6. Priority Recommendations</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=ACCENT, spaceAfter=8))

story.append(Paragraph('Based on the findings of this code review, here is a prioritized action plan organized by urgency. The items are ordered from most critical to least critical, reflecting the order in which they should be addressed to maximize security and stability improvements in the shortest time.', body_style))
story.append(Spacer(1, 8))

# Phase 1 - Immediate
story.append(Paragraph('<b>Phase 1: Immediate Action (This Week)</b>', h2_style))
phase1 = [
    '1. <b>Revoke the exposed GitHub token</b> immediately and generate a new one. Never share tokens in chat or commit them to repositories.',
    '2. <b>Add a .gitignore file</b> to the project root. Use the Flutter template and add google-services.json and firebase_options.dart to the ignore list. Remove these files from git history using git filter-branch or BFG Repo Cleaner.',
    '3. <b>Configure Firestore Security Rules</b> that validate authentication and admin roles. At minimum: users can only read/write their own bookmarks; only admin users can modify movies/genres/tags collections.',
    '4. <b>Remove the hardcoded admin email</b> from app_config.dart. Move admin detection to Firestore Custom Claims or a secure admin lookup collection that is not visible in client code.',
    '5. <b>Fix the edit_movie_page.dart backdrop bug</b> that always sets backdrop to null on save. This is causing data loss for every edit operation.',
]
for item in phase1:
    story.append(Paragraph(item, bullet_style))
story.append(Spacer(1, 12))

# Phase 2 - Short Term
story.append(Paragraph('<b>Phase 2: Short Term (Next 2 Weeks)</b>', h2_style))
phase2 = [
    '1. <b>Refactor BookmarkService and WatchlistService</b> into a shared generic base class. This eliminates approximately 200 lines of duplicated code and makes adding new collection types trivial.',
    '2. <b>Implement proper dependency injection</b> using get_it or Provider. Create service singletons that are shared across screens instead of creating new instances on every navigation.',
    '3. <b>Create all required Firestore composite indexes</b> and remove the fallback query patterns. This will halve your Firestore read costs and eliminate silent failures.',
    '4. <b>Remove dead ApiService code</b> and the empty constants.dart file. Dead code confuses new developers and increases maintenance burden.',
    '5. <b>Fix the Download Manager</b> to use path_provider for cross-platform storage paths and handle Android scoped storage permissions properly.',
]
for item in phase2:
    story.append(Paragraph(item, bullet_style))
story.append(Spacer(1, 12))

# Phase 3 - Medium Term
story.append(Paragraph('<b>Phase 3: Medium Term (Next Month)</b>', h2_style))
phase3 = [
    '1. <b>Implement a proper state management solution</b> (Riverpod recommended) for reactive data. All screens should share the same data state so that changes propagate automatically.',
    '2. <b>Add Firebase Analytics and Crashlytics</b> for production monitoring. You need visibility into user behavior and crash reports to maintain a healthy application.',
    '3. <b>Replace SharedPreferences-based storage</b> for bookmarks and downloads with Hive or Isar. SharedPreferences is not designed for large structured data and will degrade as the dataset grows.',
    '4. <b>Add unit and widget tests</b> for critical services and screens. Start with BookmarkService, FirestoreContentService, and the login flow. Target at least 50% code coverage.',
    '5. <b>Set up CI/CD with GitHub Actions</b> for automated flutter test, flutter analyze, and build verification on every pull request.',
]
for item in phase3:
    story.append(Paragraph(item, bullet_style))
story.append(Spacer(1, 12))

# Phase 4 - Long Term
story.append(Paragraph('<b>Phase 4: Long Term (Ongoing)</b>', h2_style))
phase4 = [
    '1. <b>Implement full-text search</b> using Algolia or Firebase Extensions instead of client-side filtering. This is critical for scalability as your content library grows beyond a few hundred items.',
    '2. <b>Split AppConfig into focused providers</b>: AuthProvider, ThemeProvider, LanguageProvider, and TranslationProvider. The current 595-line file is doing too much.',
    '3. <b>Extract shared UI components</b> (section titles, multi-select chips, form fields) into the components/ directory to reduce duplication across screens.',
    '4. <b>Add deep linking support</b> for sharing movie links. This improves discoverability and user engagement significantly.',
    '5. <b>Implement offline-first architecture</b> with local caching (Hive/Isar) and background sync. Users in Myanmar may experience intermittent connectivity, and the current app requires internet for all content.',
]
for item in phase4:
    story.append(Paragraph(item, bullet_style))
story.append(Spacer(1, 18))

# ══════════════════════════════════════
# 7. POSITIVE NOTES
# ══════════════════════════════════════
story.append(Paragraph('<b>7. What Is Working Well</b>', h1_style))
story.append(HRFlowable(width='100%', thickness=1, color=ACCENT, spaceAfter=8))

story.append(Paragraph('Despite the issues identified above, the project has several strengths that are worth acknowledging. These positive aspects provide a solid foundation for the improvements recommended in this review, and they demonstrate good development instincts that should be maintained as the codebase evolves.', body_style))
story.append(Spacer(1, 8))

positives = [
    '<b>Netflix-inspired UI Design:</b> The app has a polished, consistent dark theme with the Netflix-style red accent color. The Material Design 3 integration with custom color schemes for both light and dark modes shows attention to visual quality and user experience.',
    '<b>Firebase Integration:</b> The migration from REST API to Firestore is a smart architectural decision. Firestore provides real-time updates, offline support, and eliminates the need for a separate backend server. The cursor-based pagination implementation is well done.',
    '<b>Local/Cloud Data Sync:</b> The bookmark and watchlist services implement a thoughtful local-first approach with cloud sync on login. This is a good UX pattern for users who may be offline or not logged in. The merge logic prevents data loss during sync.',
    '<b>Bilingual Support:</b> The Myanmar/English translation system is comprehensive with 90+ translation keys covering all major features. This shows consideration for the local user base.',
    '<b>Download Manager Architecture:</b> The download manager with pause/resume/retry functionality and progress tracking is well-designed. The state machine approach (idle/downloading/paused/completed/failed) is clean and maintainable.',
    '<b>Age Rating Gate:</b> The 18+ content filtering with a confirmation gate is a responsible feature that shows awareness of content appropriateness, especially important for a movie app accessible to all ages.',
    '<b>Admin Panel:</b> The comprehensive admin panel with movie/series CRUD, genre/tag/collection management, and search functionality gives content managers full control without needing direct Firestore access.',
    '<b>Search with Filters:</b> The multi-dimensional search (keyword, genre, type, year, rating, sort) provides powerful content discovery. The filter UI with active filter badges is intuitive.',
]
for item in positives:
    story.append(Paragraph(item, bullet_style))

# Build
doc.build(story)
print(f"PDF generated at: {output_path}")
