import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== AUTH ====================

  // Get current user
  User? get currentUser => _auth.currentUser;
  bool get isUserLoggedIn => _auth.currentUser != null;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register with email & password
  Future<UserCredential?> registerWithEmail(String email, String password, String displayName) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await credential.user?.updateDisplayName(displayName);

      // Create user profile in Firestore
      if (credential.user != null) {
        await _createUserProfile(
          uid: credential.user!.uid,
          email: email,
          displayName: displayName,
        );
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  // Login with email & password
  Future<UserCredential?> loginWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login in Firestore
      if (credential.user != null) {
        await _firestore.collection('users').doc(credential.user!.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  // Login as Admin - verifies admin role from Firestore after auth
  Future<UserCredential?> loginAsAdmin(String username, String password) async {
    try {
      // Resolve admin email from Firestore config/admin_emails document
      String adminEmail;
      try {
        final configDoc = await _firestore.collection('config').doc('admin_emails').get();
        if (configDoc.exists) {
          final mappings = Map<String, String>.from(configDoc.data()?['mappings'] ?? {});
          adminEmail = mappings[username.toLowerCase()] ?? '$username@cmmovies.app';
        } else {
          adminEmail = '$username@cmmovies.app';
        }
      } catch (_) {
        // Fallback to standard email format if Firestore config is unavailable
        adminEmail = '${username.toLowerCase()}@cmmovies.app';
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: adminEmail,
        password: password,
      );

      // Verify admin role in Firestore
      if (credential.user != null) {
        final doc = await _firestore.collection('users').doc(credential.user!.uid).get();
        if (doc.exists && doc.data()?['role'] == 'admin') {
          return credential;
        } else {
          await _auth.signOut();
          throw Exception('Not an admin account');
        }
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Change password
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return false;

      // Re-authenticate
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Map Firebase Auth exceptions to user-friendly messages
  String _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Wrong password';
      case 'email-already-in-use':
        return 'Email is already registered';
      case 'weak-password':
        return 'Password is too weak (at least 6 characters)';
      case 'invalid-email':
        return 'Invalid email address';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return e.message ?? 'Authentication failed';
    }
  }

  // ==================== FIRESTORE ====================

  // Create user profile
  Future<void> _createUserProfile({
    required String uid,
    required String email,
    required String displayName,
    String role = 'user',
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'role': role,
      'registrationDate': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'bookmarks': [],
      'settings': {
        'darkMode': true,
        'language': 'my',
        'downloadEnabled': true,
      },
    });
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      return null;
    }
  }

  // Update user profile
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  // ==================== BOOKMARKS ====================

  // Get bookmarks stream (real-time)
  Stream<List<Map<String, dynamic>>> getBookmarksStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
              'id': doc.id,
              ...doc.data(),
            }).toList());
  }

  // Add bookmark
  Future<void> addBookmark(String uid, Map<String, dynamic> movieData) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .doc(movieData['id'].toString())
        .set({
      ...movieData,
      'addedAt': FieldValue.serverTimestamp(),
    });
  }

  // Remove bookmark
  Future<void> removeBookmark(String uid, String movieId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .doc(movieId)
        .delete();
  }

  // Check if bookmarked
  Future<bool> isBookmarked(String uid, String movieId) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .doc(movieId)
        .get();
    return doc.exists;
  }

  // Clear all bookmarks
  Future<void> clearBookmarks(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ==================== SETTINGS ====================

  // Get user settings
  Future<Map<String, dynamic>?> getUserSettings(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['settings'] as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  // Update user settings
  Future<void> updateUserSettings(String uid, Map<String, dynamic> settings) async {
    await _firestore.collection('users').doc(uid).update({
      'settings': settings,
    });
  }
}
