#!/usr/bin/env python3
"""
Phase 4.3 syntax check — verifies that the modified admin_panel_page.dart
file has balanced braces/brackets/parens, no stale references to deleted
symbols, and that all new method calls have corresponding definitions.

This is a static check; it does NOT replace `flutter analyze`. Bro will
run the real build on his machine.
"""

import re
import sys
from pathlib import Path

FILE = Path("/home/z/my-project/cm-app/lib/app/ui/screens/admin_panel_page.dart")

def main():
    src = FILE.read_text()
    lines = src.splitlines()

    errors = []
    warnings = []

    # ---- 1. Brace/bracket/paren balance ----
    balance = {'{': 0, '[': 0, '(': 0}
    pairs = {'}': '{', ']': '[', ')': '('}
    in_string = False
    string_char = None
    in_line_comment = False
    in_block_comment = False
    line_balance = []  # track per-line for diagnostics

    for i, line in enumerate(lines, 1):
        in_line_comment = False
        j = 0
        while j < len(line):
            c = line[j]
            # Handle comments
            if not in_string and not in_block_comment:
                if j + 1 < len(line) and c == '/' and line[j+1] == '/':
                    in_line_comment = True
                    break
                if j + 1 < len(line) and c == '/' and line[j+1] == '*':
                    in_block_comment = True
                    j += 2
                    continue
            if in_block_comment:
                if j + 1 < len(line) and c == '*' and line[j+1] == '/':
                    in_block_comment = False
                    j += 2
                    continue
                j += 1
                continue
            if in_line_comment:
                break
            # Handle strings
            if not in_string and c in ('"', "'"):
                # Check for raw string
                if j > 0 and line[j-1] == 'r':
                    pass  # raw string, still uses quote
                in_string = True
                string_char = c
                j += 1
                continue
            if in_string:
                if c == '\\':
                    j += 2  # skip escaped char
                    continue
                if c == string_char:
                    in_string = False
                    string_char = None
                    j += 1
                    continue
                j += 1
                continue
            # Handle brackets
            if c in '{[(':
                balance[c] += 1
            elif c in '}])':
                opener = pairs[c]
                balance[opener] -= 1
                if balance[opener] < 0:
                    errors.append(f"Line {i}: extra closing '{c}' (opener '{opener}' count went negative)")
            j += 1

    for opener, count in balance.items():
        if count != 0:
            errors.append(f"Unbalanced '{opener}' — final count: {count}")

    # ---- 2. Stale references to deleted symbols ----
    stale_patterns = [
        r'\b_pageCache\b',
        r'\b_pageLastDocs\b',
        r'\b_currentPage\b',
        r'\b_isLoadingPage\b',
        r'\b_knownPages\b',
        r'\b_loadPage\b',
        r'\b_nextPage\b',
        r'\b_prevPage\b',
        r'\b_seriesPageCache\b',
        r'\b_seriesPageLastDocs\b',
        r'\b_seriesCurrentPage\b',
        r'\b_seriesIsLoadingPage\b',
        r'\b_knownSeriesPages\b',
        r'\b_loadSeriesPage\b',
        r'\b_nextSeriesPage\b',
        r'\b_prevSeriesPage\b',
        r'\b_buildPaginationControls\b',
        r'\bisLoadingThisPage\b',
        r'\bforSeriesTab\b',
        r'\bcurrentPagePosts\b',
        r'\bcurrentSeriesPagePosts\b',
    ]
    for pat in stale_patterns:
        for m in re.finditer(pat, src):
            line_no = src[:m.start()].count('\n') + 1
            # Skip if inside a comment line
            line_text = lines[line_no - 1] if line_no <= len(lines) else ''
            stripped = line_text.lstrip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue
            warnings.append(f"Line {line_no}: stale reference '{m.group()}' in: {line_text.strip()[:100]}")

    # ---- 3. Method definitions vs calls ----
    # Find all method definitions in the class
    method_defs = set()
    for m in re.finditer(r'^\s+(?:Future<[^>]+>\s+|void\s+|Widget\s+|int\s+|bool\s+|String\s+)?(_\w+)\s*[(<]', src, re.MULTILINE):
        method_defs.add(m.group(1))

    # Check that referenced internal methods are defined
    referenced = set()
    for m in re.finditer(r'\b(_\w+)\s*\(', src):
        name = m.group(1)
        if name in ('_isLoading', '_isSearching', '_searchQuery', '_filterGenre',
                    '_filterYear', '_allPosts', '_allSeriesPosts', '_hasMore',
                    '_seriesHasMore', '_isLoadingMore', '_seriesIsLoadingMore',
                    '_lastVisibleDoc', '_seriesLastVisibleDoc', '_pageSize',
                    '_filteredPosts', '_genres', '_tags', '_collections',
                    '_bannerImageUrls', '_totalCountAll', '_totalCountMovies',
                    '_totalCountSeries', '_selectedPostIds', '_isSelecting',
                    '_isSearchingLoading', '_searchController', '_genresTagsSubTabIndex'):
            continue  # field, not method
        referenced.add(name)

    missing_defs = referenced - method_defs
    # Filter out known Flutter framework calls and other valid identifiers
    dart_builtins = {'_buildPostListItem', '_buildFilterBar', '_buildGenresTagsTab',
                     '_buildBannerTab', '_buildSimpleList', '_buildBannerUrlField',
                     '_buildBannerPreview', '_showAddOptions', '_filterPosts',
                     '_performGlobalSearch', '_applyFilters', '_bulkDeleteSelected',
                     '_deletePost', '_saveBannerConfig', '_addGenreTagDialog',
                     '_editItemDialog', '_deleteItemDialog', '_loadInitialData',
                     '_refresh', '_loadMore', '_loadMoreSeries',
                     '_buildPostsTab', '_buildPostsList', '_buildListFooter',
                     '_availableYears'}
    missing_defs -= dart_builtins
    if missing_defs:
        warnings.append(f"Referenced but possibly undefined: {missing_defs}")

    # ---- 4. Duplicate field declarations ----
    field_decls = {}
    for m in re.finditer(r'^\s+(?:static\s+)?(?:final\s+)?(?:late\s+)?(?:const\s+)?(?:List<[^>]+>\s+|bool\s+|int\s+|String\s+|DocumentSnapshot\??\s+|TabController\s+|Timer\??\s+|TextEditingController\s+|FirestoreContentService\s+|ScrollController\s+)(\w+)\s*[=;]', src, re.MULTILINE):
        name = m.group(1)
        line_no = src[:m.start()].count('\n') + 1
        if name in field_decls:
            errors.append(f"Line {line_no}: DUPLICATE field declaration '{name}' (first at line {field_decls[name]})")
        else:
            field_decls[name] = line_no

    # ---- Report ----
    print(f"=== Phase 4.3 syntax check on {FILE.name} ===")
    print(f"Total lines: {len(lines)}")
    print(f"Final brace balance: {{={balance['{']}, [= {balance['[']}, (= {balance['(']}")
    print()

    if errors:
        print(f"ERRORS ({len(errors)}):")
        for e in errors:
            print(f"  ✗ {e}")
    else:
        print("✓ No structural errors (braces/brackets/parens balanced, no duplicate fields)")

    if warnings:
        print(f"\nWARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"  ⚠ {w}")
    else:
        print("✓ No stale references to deleted symbols")

    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
