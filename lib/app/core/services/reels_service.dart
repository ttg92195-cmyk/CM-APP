// =============================================================================
// Phase 4 Step A — Reels Firestore Service (+ 2026-08-28 hotfix: null-safe
// updateReel via FieldValue.delete, fixing permission-denied on Reel edits)
// =============================================================================
// Singleton service that handles all CRUD operations for the `reels`
// Firestore collection. Modeled after FirestoreContentService but kept
// as a SEPARATE class because:
//   1. FirestoreContentService is already 3100+ lines — adding Reels there
//      would further bloat it.
//   2. Reels have a different lifecycle (no genres/tags/collections to
//      sync counts with) and don't participate in the Batch Import
//      pipeline, so the cross-cutting concerns are smaller.
//   3. Bro asked for "Reels posts သီးခြားတင်လိုရအောင်" — separate
//      tab, separate service, separate collection. The architectural
//      separation makes the feature easy to disable or remove later.
//
// All admin-only operations go through `verifyAdmin()` which reads the
// current user's Firestore user doc and checks role/isAdmin. Same pattern
// as FirestoreContentService.verifyAdmin() for consistency.
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/reel.dart';
import 'package:cm_movies/app/core/services/admin_audit_service.dart';

class ReelsService {
  ReelsService._();
  static final ReelsService instance = ReelsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CollectionReference get _reelsRef => _firestore.collection('reels');

  // ==================== ADMIN VERIFICATION ====================

  /// Returns true if the current Firebase Auth user has role='admin' OR
  /// isAdmin=true in their Firestore user doc. Mirrors
  /// FirestoreContentService.isCurrentUserAdmin exactly.
  Future<bool> isCurrentUserAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      final data = doc.data()! as Map<String, dynamic>;
      return data['role'] == 'admin' || data['isAdmin'] == true;
    } catch (e) {
      debugPrint('ReelsService.admin check failed: $e');
      return false;
    }
  }

  /// Throws if the current user is not an admin. Call at the start of
  /// every admin-only operation.
  Future<void> verifyAdmin() async {
    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception(
          'Admin permission required. You are not authorized to manage Reels.');
    }
  }

  // ==================== READ OPERATIONS ====================

  /// Fetch a page of Reels ordered by `updatedAt` descending (admin edits
  /// bump to top, same as Movies). Returns `{reels, startAfter}` where
  /// `startAfter` is the last doc's snapshot — pass it to the next call
  /// for cursor-based pagination.
  ///
  /// On the primary path failing (missing composite index), falls back
  /// to `orderBy('createdAt', descending)` then to a no-order query so
  /// the UI never appears empty just because an index isn't deployed.
  Future<Map<String, dynamic>> getReels({
    int limit = 30,
    DocumentSnapshot? startAfter,
  }) async {
    // PRIMARY: orderBy('updatedAt', descending)
    try {
      Query query = _reelsRef
          .orderBy('updatedAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final reels = snapshot.docs
          .map((doc) => Reel.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
      return {
        'reels': reels,
        'startAfter': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('ReelsService.getReels primary path failed: $e');
    }

    // SECONDARY: orderBy('createdAt', descending) — doesn't need a
    // composite index. Useful when the primary index isn't deployed.
    try {
      Query query = _reelsRef
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final reels = snapshot.docs
          .map((doc) => Reel.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
      return {
        'reels': reels,
        'startAfter': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('ReelsService.getReels secondary path failed: $e');
    }

    // TERTIARY: no orderBy, just limit. Last-resort fallback so the UI
    // never appears empty just because indexes aren't deployed.
    try {
      final snapshot = await _reelsRef.limit(limit).get();
      final reels = snapshot.docs
          .map((doc) => Reel.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
      return {
        'reels': reels,
        'startAfter': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('ReelsService.getReels tertiary path failed: $e');
      return {'reels': <Reel>[], 'startAfter': null};
    }
  }

  /// Fetch trending Reels (where `isTrending == true`). Used by the
  /// Reels tab's "Trending" header row if we add one in a later step.
  /// For Phase 4 Step A, this is a placeholder — the basic grid will
  /// just call getReels() without filtering.
  Future<List<Reel>> getTrendingReels({int limit = 10}) async {
    try {
      final snapshot = await _reelsRef
          .where('isTrending', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => Reel.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      debugPrint('ReelsService.getTrendingReels failed: $e');
      return [];
    }
  }

  /// Fetch a single Reel by id. Returns null if not found or on error.
  Future<Reel?> getReelById(String id) async {
    try {
      final doc = await _reelsRef.doc(id).get();
      if (!doc.exists) return null;
      return Reel.fromMap(
        doc.data() as Map<String, dynamic>,
        docId: doc.id,
      );
    } catch (e) {
      debugPrint('ReelsService.getReelById failed: $e');
      return null;
    }
  }

  /// Case-insensitive title search. Uses `title_lowercase` field which
  /// the client populates on create/update. Returns up to [limit] matches.
  /// Uses prefix match (`isGreaterThanOrEqualTo` + `isLessThan` trick) so
  /// "Spi" matches "Spider-Man" but "ider-Man" does not match. Same pattern
  /// as FirestoreContentService.searchMoviesByTitle for consistency.
  Future<List<Reel>> searchReels(String query, {int limit = 20}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];
    try {
      final endQuery = normalized.substring(0, normalized.length - 1) +
          String.fromCharCode(normalized.codeUnitAt(normalized.length - 1) + 1);
      final snapshot = await _reelsRef
          .where('title_lowercase', isGreaterThanOrEqualTo: normalized)
          .where('title_lowercase', isLessThan: endQuery)
          .orderBy('title_lowercase')
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => Reel.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      debugPrint('ReelsService.searchReels failed: $e');
      return [];
    }
  }

  // ==================== ADMIN CRUD OPERATIONS ====================

  /// Create a new Reel (admin only). Returns the new doc id.
  ///
  /// Sets `createdAt` + `updatedAt` to serverTimestamp so the new Reel
  /// sorts at the top of the `orderBy('updatedAt', descending)` query.
  Future<String> addReel(Reel reel) async {
    await verifyAdmin();
    final now = FieldValue.serverTimestamp();
    final data = reel.toMap();
    // Set admin-managed timestamps; remove client-supplied values to
    // avoid clock-skew issues.
    data
      ..remove('createdAt')
      ..remove('updatedAt')
      ..['createdAt'] = now
      ..['updatedAt'] = now
      ..['likeCount'] = 0; // Always start at 0 likes — never trust client.
    final docRef = await _reelsRef.add(data);

    // Audit log (best-effort, never throws).
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.reelCreate,
      collection: AdminAuditCollection.reels,
      docId: docRef.id,
      details: {
        'title': reel.title,
        'hasEpisodes': reel.episodes.isNotEmpty,
        'episodeCount': reel.episodes.length,
        'hasDownloadLinks': reel.downloadLinks.isNotEmpty,
      },
    ));
    return docRef.id;
  }

  /// Update an existing Reel (admin only). Accepts a partial update map
  /// so the admin UI can patch just the fields the user edited.
  ///
  /// NULL HANDLING (Phase 4 hotfix, 2026-08-28): the Admin Reels form
  /// sends `description: null` / `posterUrl: null` when those optional
  /// fields are left empty. An explicit null in an update patch makes the
  /// post-write document contain null for that field, and the security
  /// rules (isValidReel) validate optional string fields as `is string`
  /// whenever present — `null is string` fails, so the ENTIRE update was
  /// rejected with [cloud_firestore/permission-denied]. Create never hit
  /// this because Reel.toMap() omits null fields entirely.
  ///
  /// Fix: every null value in [data] is converted to FieldValue.delete()
  /// BEFORE the write. Deleting the field (a) removes any previously
  /// stored value — matching the admin's intent of clearing the field —
  /// and (b) leaves the field ABSENT in the post-write doc, which passes
  /// rules validation.
  Future<void> updateReel(String id, Map<String, dynamic> data) async {
    await verifyAdmin();

    // Convert null values to FieldValue.delete() — never write nulls.
    // (Update rules evaluate the merged post-write doc: a deleted field
    // is simply absent, which is valid for all optional Reel fields.)
    final nullKeys = data.keys.where((k) => data[k] == null).toList(growable: false);
    for (final key in nullKeys) {
      data[key] = FieldValue.delete();
    }

    // Auto-update derived fields when title changes.
    // Defensive `is String` check instead of a cast: after the conversion
    // above, a null title would be a FieldValue (cast would throw).
    final titleValue = data['title'];
    if (titleValue is String && titleValue.isNotEmpty) {
      data['title_lowercase'] = titleValue.toLowerCase();
      // Auto-generate slug if not explicitly provided.
      if (!data.containsKey('slug')) {
        data['slug'] = _generateSlug(titleValue);
      }
    }
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _reelsRef.doc(id).update(data);

    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.reelUpdate,
      collection: AdminAuditCollection.reels,
      docId: id,
      details: {
        'fieldsChanged': data.keys.toList(),
      },
    ));
  }

  /// Delete a Reel (admin only).
  Future<void> deleteReel(String id) async {
    await verifyAdmin();
    // Read title BEFORE delete so the audit log records what was removed.
    String? deletedTitle;
    try {
      final doc = await _reelsRef.doc(id).get();
      if (doc.exists) {
        deletedTitle = (doc.data() as Map<String, dynamic>?)?['title'] as String?;
      }
    } catch (_) {}
    await _reelsRef.doc(id).delete();

    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.reelDelete,
      collection: AdminAuditCollection.reels,
      docId: id,
      details: {
        'title': deletedTitle,
      },
    ));
  }

  // ==================== USER INTERACTIONS ====================

  /// Atomically increment the likeCount on a Reel by [+1 / -1] depending
  /// on [unlike]. Uses Firestore.FieldValue.increment so concurrent likes
  /// don't race. Returns the new likeCount, or null on error.
  ///
  /// NOTE: This is a denormalized counter. Per-user like state (so the
  /// same user can't like twice) should live in a per-user subcollection
  /// `users/{uid}/reel_likes/{reelId}`. That subcollection is NOT created
  /// in Phase 4 Step A — it's deferred to Step E (Reels Video Player) where
  /// the Like button lives. For now, addReel sets likeCount=0 and this
  /// method exists so Step E can call it without further service changes.
  Future<int?> incrementLikeCount(String reelId, {bool unlike = false}) async {
    try {
      final docRef = _reelsRef.doc(reelId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;
        // Cast snap.data() to Map<String, dynamic> explicitly because
        // Transaction.get() returns DocumentSnapshot<Object?> in newer
        // cloud_firestore versions — the `[]` operator needs a Map cast.
        final data = snap.data() as Map<String, dynamic>?;
        final current = (data?['likeCount'] as int?) ?? 0;
        final next = unlike
            ? (current > 0 ? current - 1 : 0)
            : current + 1;
        tx.update(docRef, {'likeCount': next});
      });
      // Read back the latest count for the caller.
      final fresh = await docRef.get();
      final freshData = fresh.data() as Map<String, dynamic>?;
      return (freshData?['likeCount'] as int?) ?? 0;
    } catch (e) {
      debugPrint('ReelsService.incrementLikeCount failed: $e');
      return null;
    }
  }

  // ==================== HELPERS ====================

  /// Generate a URL-safe slug from a title. Same algorithm as
  /// FirestoreContentService._generateSlug for consistency.
  String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
  }
}
