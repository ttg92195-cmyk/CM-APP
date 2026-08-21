// =============================================================================
// Phase 4 Step A — Reel model round-trip test
// =============================================================================
// Standalone Dart entry point that:
//   1. Constructs a Reel with all fields populated.
//   2. Calls toMap() → fromMap() round-trip.
//   3. Verifies all fields are preserved.
//   4. Constructs a multi-episode Reel and tests videoUrlForEpisode().
//   5. Tests defensive parsing on a corrupted map.
//
// Run via:
//   cd /home/z/my-project/CM-APP && dart run scripts/phase4_step_a_reel_test.dart
//
// Note: This is a pure-Dart script (no Flutter imports). It only depends
// on cloud_firestore's Timestamp class. To avoid pulling in Flutter, run
// this from the CM-APP project root where dart pub get has already been
// run and the cloud_firestore package is available.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/app/core/models/reel.dart';

void main() {
  print('=== Phase 4 Step A — Reel model round-trip test ===\n');

  // ---------------------------------------------------------------
  // Test 1: Full round-trip with all fields populated
  // ---------------------------------------------------------------
  print('[Test 1] Full round-trip with all fields populated...');
  final original = Reel(
    id: 'test-reel-1',
    title: 'Spider-Man No Way Home — Tom Holland Interview',
    titleLowercase: 'spider-man no way home — tom holland interview',
    slug: 'spider-man-no-way-home-tom-holland-interview',
    description: 'Behind the scenes with Tom Holland.',
    posterUrl: 'https://example.com/poster.jpg',
    videoUrl: 'https://example.com/video.mp4',
    episodes: [
      const ReelEpisode(title: 'Episode 1', videoUrl: 'https://example.com/ep1.mp4'),
      const ReelEpisode(title: 'Episode 2', videoUrl: 'https://example.com/ep2.mp4'),
    ],
    downloadLinks: const ['https://example.com/download1.mp4'],
    likeCount: 42,
    isTrending: true,
    createdAt: DateTime(2026, 8, 21, 10, 0, 0),
    updatedAt: DateTime(2026, 8, 21, 11, 0, 0),
  );
  final map = original.toMap();
  final reconstructed = Reel.fromMap(map, docId: 'test-reel-1');
  assert(reconstructed.id == original.id, 'id mismatch');
  assert(reconstructed.title == original.title, 'title mismatch');
  assert(reconstructed.titleLowercase == original.titleLowercase, 'titleLowercase mismatch');
  assert(reconstructed.slug == original.slug, 'slug mismatch');
  assert(reconstructed.description == original.description, 'description mismatch');
  assert(reconstructed.posterUrl == original.posterUrl, 'posterUrl mismatch');
  assert(reconstructed.videoUrl == original.videoUrl, 'videoUrl mismatch');
  assert(reconstructed.episodes.length == original.episodes.length, 'episodes length mismatch');
  assert(reconstructed.episodes[0].title == original.episodes[0].title, 'ep0 title mismatch');
  assert(reconstructed.episodes[1].videoUrl == original.episodes[1].videoUrl, 'ep1 videoUrl mismatch');
  assert(reconstructed.downloadLinks.length == original.downloadLinks.length, 'downloadLinks length mismatch');
  assert(reconstructed.likeCount == original.likeCount, 'likeCount mismatch');
  assert(reconstructed.isTrending == original.isTrending, 'isTrending mismatch');
  print('  PASS — all fields preserved through toMap()→fromMap() round-trip.\n');

  // ---------------------------------------------------------------
  // Test 2: Helpers — hasEpisodes, episodeCount, videoUrlForEpisode
  // ---------------------------------------------------------------
  print('[Test 2] Helpers on multi-episode Reel...');
  assert(original.hasEpisodes, 'hasEpisodes should be true for 2-episode Reel');
  assert(original.episodeCount == 2, 'episodeCount should be 2');
  assert(original.videoUrlForEpisode(0) == 'https://example.com/ep1.mp4', 'videoUrlForEpisode(0) mismatch');
  assert(original.videoUrlForEpisode(1) == 'https://example.com/ep2.mp4', 'videoUrlForEpisode(1) mismatch');
  assert(original.videoUrlForEpisode(2) == null, 'videoUrlForEpisode(2) should be null (out of range)');
  assert(original.episodeTitleForIndex(0) == 'Episode 1', 'episodeTitleForIndex(0) mismatch');
  assert(original.episodeTitleForIndex(1) == 'Episode 2', 'episodeTitleForIndex(1) mismatch');
  print('  PASS — helpers return expected values.\n');

  // ---------------------------------------------------------------
  // Test 3: Single-video Reel (no episodes list)
  // ---------------------------------------------------------------
  print('[Test 3] Single-video Reel (no episodes list)...');
  final single = Reel(
    id: 'reel-2',
    title: 'Quick Trailer',
    titleLowercase: 'quick trailer',
    videoUrl: 'https://example.com/trailer.mp4',
  );
  assert(!single.hasEpisodes, 'hasEpisodes should be false for single-video Reel');
  assert(single.episodeCount == 1, 'episodeCount should be 1 even with no episodes list');
  assert(single.videoUrlForEpisode(0) == 'https://example.com/trailer.mp4', 'videoUrlForEpisode(0) should be main videoUrl');
  assert(single.videoUrlForEpisode(1) == null, 'videoUrlForEpisode(1) should be null for single-video Reel');
  assert(single.episodeTitleForIndex(0) == 'Quick Trailer', 'episodeTitleForIndex(0) should be reel title for single-video Reel');
  print('  PASS — single-video Reel behaves correctly.\n');

  // ---------------------------------------------------------------
  // Test 4: Defensive parsing on corrupted map
  // ---------------------------------------------------------------
  print('[Test 4] Defensive parsing on corrupted map...');
  final corruptedMap = <String, dynamic>{
    'title': 12345, // wrong type — should fall back to empty string
    'videoUrl': ['not', 'a', 'string'], // wrong type — should fall back to empty string
    'episodes': 'not a list', // wrong type — should fall back to empty list
    'likeCount': 'not-a-number', // unparseable — should fall back to null→0
    'isTrending': 1, // int instead of bool — should coerce to true
    'downloadLinks': 'single url as string', // string instead of list — should wrap
    'createdAt': Timestamp.now(),
  };
  Reel? corrupted;
  try {
    corrupted = Reel.fromMap(corruptedMap, docId: 'corrupt-1');
    // Should NOT throw.
  } catch (e) {
    print('  FAIL — defensive parser threw on corrupted map: $e');
    rethrow;
  }
  assert(corrupted.title == '', 'title should fall back to empty string');
  assert(corrupted.videoUrl == '', 'videoUrl should fall back to empty string');
  assert(corrupted.episodes.isEmpty, 'episodes should fall back to empty list');
  assert(corrupted.likeCount == 0, 'likeCount should fall back to 0');
  assert(corrupted.isTrending == true, 'isTrending should coerce int 1 to true');
  assert(corrupted.downloadLinks.length == 1, 'downloadLinks string should wrap to 1-element list');
  assert(corrupted.downloadLinks[0] == 'single url as string', 'downloadLinks[0] should be the trimmed string');
  print('  PASS — corrupted map does not throw, fields fall back to safe defaults.\n');

  // ---------------------------------------------------------------
  // Test 5: timeAgo helper
  // ---------------------------------------------------------------
  print('[Test 5] timeAgo helper...');
  final oldReel = Reel(
    id: 'old',
    title: 'Old Reel',
    titleLowercase: 'old reel',
    videoUrl: 'x',
    createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 5)),
  );
  final ago = oldReel.timeAgo;
  print('  timeAgo = "$ago"');
  assert(ago.contains('day'), 'timeAgo should contain "day" for 3-day-old Reel');
  print('  PASS — timeAgo returns expected format.\n');

  // ---------------------------------------------------------------
  // Test 6: copyWith helper
  // ---------------------------------------------------------------
  print('[Test 6] copyWith helper...');
  final updated = original.copyWith(likeCount: 100, isTrending: false);
  assert(updated.id == original.id, 'id should be preserved');
  assert(updated.title == original.title, 'title should be preserved');
  assert(updated.likeCount == 100, 'likeCount should be updated');
  assert(updated.isTrending == false, 'isTrending should be updated');
  assert(original.likeCount == 42, 'original should NOT be mutated');
  print('  PASS — copyWith returns a new Reel with selective field updates.\n');

  print('=== ALL TESTS PASSED — Phase 4 Step A Reel model verified. ===');
}
