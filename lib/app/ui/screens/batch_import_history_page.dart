import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/batch_import_service.dart';

/// Full-screen page that lists past Batch Import runs from the
/// `batch_imports` Firestore collection.
///
/// Each row is a [BatchImportAuditSummary] showing timestamp, source file
/// name, total/created/updated/failed/skipped counts and duration. Tapping
/// a row pushes a [BatchImportAuditDetailPage] that shows the full record
/// including failed-item details and sample created/updated titles.
///
/// The page uses a one-shot FutureBuilder — we don't need a live stream
/// because past imports don't change after they're written. Pull-to-refresh
/// is supported via RefreshIndicator.
class BatchImportHistoryPage extends StatefulWidget {
  const BatchImportHistoryPage({super.key});

  @override
  State<BatchImportHistoryPage> createState() =>
      _BatchImportHistoryPageState();
}

class _BatchImportHistoryPageState extends State<BatchImportHistoryPage> {
  final BatchImportService _service = BatchImportService();
  late Future<List<BatchImportAuditSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listImports(limit: 50);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _service.listImports(limit: 50);
    });
    // Wait for the future to complete so RefreshIndicator dismisses cleanly.
    try {
      await _future;
    } catch (_) {
      // The FutureBuilder will display the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Import History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFFE50914),
          onRefresh: _refresh,
          child: FutureBuilder<List<BatchImportAuditSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                  ),
                );
              }

              if (snapshot.hasError) {
                return _buildErrorView(snapshot.error.toString(), isDark);
              }

              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return _buildEmptyView(isDark);
              }

              return ListView.separated(
                // Important: ListView must always be scrollable for
                // RefreshIndicator to work, even with few items.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return _HistoryTile(
                    summary: item,
                    isDark: isDark,
                    onTap: () async {
                      final shouldRefresh = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BatchImportAuditDetailPage(auditId: item.id),
                        ),
                      );
                      // If the detail page deleted the record, refresh.
                      if (shouldRefresh == true && mounted) {
                        _refresh();
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.history,
          size: 64,
          color: isDark ? Colors.white24 : Colors.black12,
        ),
        const SizedBox(height: 16),
        Text(
          'No imports yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Past batch imports will appear here, with full audit details.\nPull down to refresh.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white38 : Colors.black38,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(String error, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.error_outline,
          size: 56,
          color: Colors.red.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          'Failed to load history',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE50914),
              side: const BorderSide(color: Color(0xFFE50914)),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row in the history list.
class _HistoryTile extends StatelessWidget {
  final BatchImportAuditSummary summary;
  final bool isDark;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.summary,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFailures = summary.failed > 0 || summary.failedItemCount > 0;
    final accent = summary.cancelled
        ? Colors.blueGrey
        : (hasFailures ? Colors.orange : Colors.green);

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status dot
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title line: file name or "Import"
                    Text(
                      summary.sourceFileName ?? 'Import',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Meta line: timestamp + admin + duration
                    Text(
                      _formatMetaLine(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Counters row
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _miniChip('Total', summary.total, Colors.blueGrey),
                        _miniChip('New', summary.created, Colors.green),
                        _miniChip('Updated', summary.updated, Colors.orange),
                        _miniChip('Failed', summary.failed, Colors.red),
                        if (summary.skipped > 0)
                          _miniChip(
                              'Skipped', summary.skipped, Colors.blueGrey),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Chevron
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.white24 : Colors.black26,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "19 Jun 2026, 14:30 • 1.2s • admin@example.com"
  String _formatMetaLine() {
    final parts = <String>[];
    if (summary.startedAt != null) {
      parts.add(_formatDateTime(summary.startedAt!));
    }
    if (summary.durationMs != null) {
      parts.add(_formatDuration(summary.durationMs!));
    }
    if (summary.adminEmail != null && summary.adminEmail!.isNotEmpty) {
      parts.add(summary.adminEmail!);
    } else if (summary.cancelled) {
      parts.add('cancelled');
    }
    return parts.join('  •  ');
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '${m}m ${s}s';
  }

  Widget _miniChip(String label, int value, MaterialColor color) {
    if (value == 0 && label != 'Total') {
      // Hide zero counters except Total — keeps the row compact.
      return const SizedBox(width: 0, height: 0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Detail view for a single audit record — shows full failed-items list,
/// sample created/updated titles, and a Delete button (handy for cleaning
/// up accidental test runs).
class BatchImportAuditDetailPage extends StatefulWidget {
  final String auditId;

  const BatchImportAuditDetailPage({super.key, required this.auditId});

  @override
  State<BatchImportAuditDetailPage> createState() =>
      _BatchImportAuditDetailPageState();
}

class _BatchImportAuditDetailPageState
    extends State<BatchImportAuditDetailPage> {
  final BatchImportService _service = BatchImportService();
  late Future<BatchImportAuditRecord> _future;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getImport(widget.auditId);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete audit record?'),
        content: const Text(
          'This only removes the history entry. Any movies that were '
          'actually imported will remain in Firestore. This action '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _service.deleteImport(widget.auditId);
      if (!mounted) return;
      Navigator.of(context).pop(true); // tell list to refresh
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Import Details'),
        actions: [
          if (_isDeleting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete record',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<BatchImportAuditRecord>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                ),
              );
            }
            if (snapshot.hasError) {
              return _DetailErrorView(
                error: snapshot.error.toString(),
                isDark: isDark,
              );
            }
            final rec = snapshot.data!;
            return _DetailBody(record: rec, isDark: isDark);
          },
        ),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  final String error;
  final bool isDark;
  const _DetailErrorView({required this.error, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text(
              'Could not load record',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final BatchImportAuditRecord record;
  final bool isDark;
  const _DetailBody({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overview',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _kv('File', record.sourceFileName ?? '(unknown)'),
              _kv('Started', _fmt(record.startedAt)),
              _kv('Finished', _fmt(record.completedAt)),
              _kv(
                'Duration',
                record.durationMs == null
                    ? '—'
                    : '${record.durationMs} ms',
              ),
              _kv('Admin', record.adminEmail ?? record.id.substring(0, 8)),
              if (record.cancelled)
                _kv('Status', 'Cancelled (partial)')
              else if (record.failed > 0)
                _kv('Status', 'Completed with failures')
              else
                _kv('Status', 'Success'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Big counters
        _sectionCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Counts',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _bigCounter('Total', record.total, Colors.blueGrey),
                  _bigCounter('Created', record.created, Colors.green),
                  _bigCounter('Updated', record.updated, Colors.orange),
                  _bigCounter('Failed', record.failed, Colors.red),
                ],
              ),
              if (record.skipped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Skipped: ${record.skipped} (invalid schema or cancelled)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Failed items
        if (record.failedItems.isNotEmpty) ...[
          _sectionCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Text(
                      'Failed Items (${record.failedItems.length}'
                      '${record.failedItemCount > record.failedItems.length ? " of ${record.failedItemCount}" : ""})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...record.failedItems.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${f['sourceIndex']}',
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (f['title'] ?? '(untitled)').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (f['error'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  f['error'].toString(),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                    height: 1.3,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Sample created
        if (record.sampleCreated.isNotEmpty) ...[
          _sectionCard(
            isDark: isDark,
            child: _sampleList(
              title: 'Sample Created (${record.sampleCreated.length}'
                  '${record.created > record.sampleCreated.length ? " of ${record.created}" : ""})',
              titles: record.sampleCreated,
              color: Colors.green,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Sample updated
        if (record.sampleUpdated.isNotEmpty) ...[
          _sectionCard(
            isDark: isDark,
            child: _sampleList(
              title: 'Sample Updated(${record.sampleUpdated.length}'
                  '${record.updated > record.sampleUpdated.length ? " of ${record.updated}" : ""})',
              titles: record.sampleUpdated,
              color: Colors.orange,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _sectionCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigCounter(String label, int value, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sampleList({
    required String title,
    required List<String> titles,
    required MaterialColor color,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: titles
              .map(
                (t) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
