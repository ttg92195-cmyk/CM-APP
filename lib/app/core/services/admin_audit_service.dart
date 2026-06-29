// Admin audit log service — Phase 2.4
//
// Records admin actions (movie create/update/delete, genre/tag/collection
// CRUD, banner update, user ban/unban/VIP/forceLogout/roleChange,
// batch_import start/complete/delete, notification delete) to a Firestore
// `admin_audit` collection for accountability.
//
// Design principles:
//   1. **Never break the main action.** Every audit-log call is wrapped in
//      try/catch. If the audit write fails (network, rules not deployed,
//      schema mismatch), the error is swallowed via debugPrint. The user's
//      primary action (e.g., adding a movie) MUST still succeed.
//   2. **Fire-and-forget.** Audit writes happen AFTER the main action
//      succeeds. We don't await the audit write in callers (except where
//      noted) to avoid slowing down user-facing operations. The record()
//      method itself is async but callers use `unawaited()`.
//   3. **Immutable.** Once written, audit entries cannot be updated or
//      deleted — enforced by firestore.rules (`allow update, delete: if false`).
//      Bro can still delete via Firebase Console directly if needed for
//      compliance cleanup, but no client (not even admin) can rewrite
//      history.
//   4. **Schema-validated.** The firestore.rules `isValidAuditEntry()`
//      helper enforces required fields (action, collection, adminUid,
//      timestamp) and types so a compromised admin client cannot pollute
//      the audit log with garbage.
//   5. **Freeform `details`.** Different actions need different context
//      (movie title for movie.create, ban state for user.ban, VIP days
//      for user.vip_grant). The `details` map is freeform to accommodate
//      this, but is capped at small size to stay well under Firestore's
//      1 MiB doc limit.
//   6. **No PII in details beyond what's already in target collections.**
//      User email is not stored in audit details (it's already in the
//      `users` collection doc). For user.ban / user.vip_grant etc., we
//      store only the target UID + the change made.

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Standard action names for the `action` field in audit entries.
///
/// Using constants instead of raw strings prevents typos in callers and
/// makes grep/refactor trivial. New actions should be added here.
class AdminAuditAction {
  AdminAuditAction._();

  // Movies
  static const movieCreate = 'movie.create';
  static const movieUpdate = 'movie.update';
  static const movieDelete = 'movie.delete';

  // Genres / Tags / Collections (share schema, but actions are distinct
  // so the audit log clearly shows which sub-collection was touched).
  static const genreCreate = 'genre.create';
  static const genreUpdate = 'genre.update';
  static const genreDelete = 'genre.delete';
  static const tagCreate = 'tag.create';
  static const tagUpdate = 'tag.update';
  static const tagDelete = 'tag.delete';
  static const collectionCreate = 'collection.create';
  static const collectionUpdate = 'collection.update';
  static const collectionDelete = 'collection.delete';

  // Banner config (app_settings/banner_config)
  static const bannerUpdate = 'banner.update';

  // Notifications (only delete — Phase 1.1 stopped creates)
  static const notificationDelete = 'notification.delete';

  // Batch imports
  static const batchImportComplete = 'batch_import.complete';
  static const batchImportDelete = 'batch_import.delete';

  // User admin actions
  static const userBan = 'user.ban';
  static const userUnban = 'user.unban';
  static const userForceLogout = 'user.force_logout';
  static const userRoleChange = 'user.role_change';
  static const userVipGrant = 'user.vip_grant';
  static const userVipRevoke = 'user.vip_revoke';
}

/// Standard collection names for the `collection` field.
class AdminAuditCollection {
  AdminAuditCollection._();

  static const movies = 'movies';
  static const genres = 'genres';
  static const tags = 'tags';
  static const collections = 'collections';
  static const appSettings = 'app_settings';
  static const notifications = 'notifications';
  static const batchImports = 'batch_imports';
  static const users = 'users';
}

/// Singleton service that writes audit entries to `admin_audit/{autoId}`.
///
/// Usage:
///   unawaited(AdminAuditService.instance.record(
///     action: AdminAuditAction.movieCreate,
///     collection: AdminAuditCollection.movies,
///     docId: newMovieId,
///     details: {'title': 'Inception', 'tmdbId': 12345},
///   ));
///
/// The `record()` method:
///   - Reads adminUid + adminEmail from FirebaseAuth.instance.currentUser
///   - Reads appVersion from the APP_VERSION String.fromEnvironment
///   - Writes a single doc to admin_audit collection
///   - Catches and logs all errors via debugPrint (never throws)
class AdminAuditService {
  AdminAuditService._();
  static final AdminAuditService instance = AdminAuditService._();

  static const String _collectionName = 'admin_audit';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Maximum number of keys allowed in the `details` map. Capped to keep
  /// the audit doc small and within Firestore's 1 MiB doc limit even with
  /// large string values. Callers should keep details concise — title,
  /// IDs, short status strings — not entire movie payloads.
  static const int _maxDetailsKeys = 20;

  /// Write a single audit entry. Returns the doc ID on success, null on
  /// failure (caller can ignore the return value — audit writes are
  /// best-effort).
  ///
  /// [action] — one of the AdminAuditAction.* constants.
  /// [collection] — one of the AdminAuditCollection.* constants.
  /// [docId] — the target document ID (optional; some actions like
  ///   banner.update don't have a meaningful docId).
  /// [details] — freeform map of context (title, ban state, VIP days, etc.).
  ///   Capped at [_maxDetailsKeys] entries; extra keys are dropped silently.
  /// [success] — defaults to true. Set to false to record an action that
  ///   was attempted but failed (e.g., a movie add that threw). This is
  ///   useful for forensic analysis of attack attempts.
  Future<String?> record({
    required String action,
    required String collection,
    String? docId,
    Map<String, dynamic>? details,
    bool success = true,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        // Not signed in — can't record audit. This should never happen
        // because all callers are gated behind _requireAdmin(), but we
        // guard defensively.
        debugPrint('AdminAuditService: skipping audit (no signed-in user) '
            'action=$action collection=$collection');
        return null;
      }

      // Cap details map size — drop extra keys to keep doc small.
      Map<String, dynamic> safeDetails = {};
      if (details != null) {
        int count = 0;
        for (final entry in details.entries) {
          if (count >= _maxDetailsKeys) break;
          safeDetails[entry.key] = entry.value;
          count++;
        }
      }

      // String.fromEnvironment is compile-time constant; reading it inside
      // the method is fine because the compiler inlines the value at
      // build time. The defaultValue handles local dev runs without
      // --dart-define.
      const appVersion = String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'unknown',
      );

      final payload = <String, dynamic>{
        'action': action,
        'collection': collection,
        'adminUid': user.uid,
        'adminEmail': user.email ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
        'success': success,
        'details': safeDetails,
      };

      // docId is optional — only include if provided. Keeping it out when
      // null avoids storing a null field that would clutter the audit log
      // viewer (banner.update has no meaningful docId, for example).
      if (docId != null && docId.isNotEmpty) {
        payload['docId'] = docId;
      }

      final docRef = await _firestore
          .collection(_collectionName)
          .add(payload);
      return docRef.id;
    } catch (e, stack) {
      // CRITICAL: never throw from audit-log. The caller's primary action
      // has already succeeded; a failed audit write should not roll back
      // or surface an error to the user. Log via debugPrint so devs can
      // see it during development, but in release builds this is silent.
      //
      // If Firebase Crashlytics is initialized (Phase 2.5), we could also
      // record this as a non-fatal error. But importing Crashlytics here
      // would create a circular dependency (Crashlytics init code might
      // call audit-log in the future). Keep it simple — debugPrint only.
      debugPrint('AdminAuditService: FAILED to record audit '
          'action=$action collection=$collection error=$e\n$stack');
      return null;
    }
  }

  /// Convenience method for recording a FAILED action. Same as record()
  /// with success=false, but with an additional [error] field in details
  /// so the audit log shows what went wrong.
  Future<String?> recordFailure({
    required String action,
    required String collection,
    String? docId,
    required Object error,
    Map<String, dynamic>? details,
  }) async {
    final enrichedDetails = <String, dynamic>{
      ...(details ?? {}),
      'error': error.toString(),
    };
    // Truncate the error string to 1000 chars to avoid blowing up the
    // audit doc size if the error is a giant stack trace.
    final errStr = enrichedDetails['error'] as String;
    if (errStr.length > 1000) {
      enrichedDetails['error'] = '${errStr.substring(0, 1000)}...[truncated]';
    }
    return record(
      action: action,
      collection: collection,
      docId: docId,
      details: enrichedDetails,
      success: false,
    );
  }
}
