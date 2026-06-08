import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/notification_model.dart';
import 'package:cm_movies/app/core/services/fcm_notification_service.dart';

/// Admin Notification Page — allows admins to compose and send push notifications
/// to all users, and view notification history.
///
/// Flow:
/// 1. Admin fills in Title, Body, and optional Movie ID/Slug
/// 2. Taps "Send Notification"
/// 3. Notification is saved to Firestore `notifications` collection
/// 4. A Cloud Function triggers on the new document and sends FCM push to `movies_all` topic
/// 5. All subscribed devices receive the push notification
class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _movieIdController = TextEditingController();
  final _movieSlugController = TextEditingController();

  bool _isSending = false;
  bool _includeMovieLink = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _movieIdController.dispose();
    _movieSlugController.dispose();
    super.dispose();
  }

  /// Send notification: saves to Firestore and triggers Cloud Function push
  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Notification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send this notification to all users?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE50914).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleController.text.trim(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _bodyController.text.trim(),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final notification = NotificationModel(
        id: '', // Firestore will auto-generate
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        movieId: _includeMovieLink && _movieIdController.text.trim().isNotEmpty
            ? _movieIdController.text.trim()
            : null,
        movieSlug: _includeMovieLink && _movieSlugController.text.trim().isNotEmpty
            ? _movieSlugController.text.trim()
            : null,
        sentBy: user.email ?? user.uid,
        sentAt: DateTime.now(),
        isSent: false, // Will be updated after OneSignal confirms
      );

      // Save to Firestore for history tracking
      final docRef = await FirebaseFirestore.instance
          .collection('notifications')
          .add(notification.toFirestore());

      // Send push notification via OneSignal REST API (free, no server needed)
      final sent = await FcmNotificationService().sendNotificationToAll(
        title: notification.title,
        body: notification.body,
        movieId: notification.movieId,
        movieSlug: notification.movieSlug,
      );

      // Update Firestore with send status
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(docRef.id)
          .update({'isSent': sent});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sent
                ? 'Notification sent successfully!'
                : 'Notification saved but push failed. Check OneSignal config.'),
            backgroundColor: sent ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Clear form
        _titleController.clear();
        _bodyController.clear();
        _movieIdController.clear();
        _movieSlugController.clear();
        setState(() {
          _includeMovieLink = false;
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Delete a notification from Firestore
  Future<void> _deleteNotification(String notificationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notification'),
        content: const Text('Are you sure you want to delete this notification?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(notificationId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.send), text: 'Compose'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ===== COMPOSE TAB =====
            _buildComposeTab(isDark),
            // ===== HISTORY TAB =====
            _buildHistoryTab(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE50914).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: Color(0xFFE50914),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Push Notification',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Send to all subscribed users',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Title field
            Text(
              'Notification Title',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
              decoration: InputDecoration(
                hintText: 'e.g. New Movie Added!',
                prefixIcon: const Icon(Icons.title, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 16),

            // Body field
            Text(
              'Notification Body',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bodyController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Body is required' : null,
              decoration: InputDecoration(
                hintText: 'e.g. Check out the latest blockbuster movie...',
                prefixIcon: const Icon(Icons.message, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 4,
              minLines: 2,
              maxLength: 500,
            ),
            const SizedBox(height: 16),

            // Movie link toggle
            SwitchListTile(
              value: _includeMovieLink,
              onChanged: (val) => setState(() => _includeMovieLink = val),
              title: const Text(
                'Link to Movie',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                'When tapped, opens a specific movie detail page',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
              ),
              activeColor: const Color(0xFFE50914),
              contentPadding: EdgeInsets.zero,
            ),

            // Movie ID & Slug fields (shown when toggle is on)
            if (_includeMovieLink) ...[
              const SizedBox(height: 12),
              Text(
                'Movie Slug',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _movieSlugController,
                decoration: InputDecoration(
                  hintText: 'e.g. the-dark-knight-2008',
                  prefixIcon: const Icon(Icons.link, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The slug from the movie URL. Users will navigate to this movie when they tap the notification.',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
              ),
              const SizedBox(height: 12),
              Text(
                'Movie ID (optional)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _movieIdController,
                decoration: InputDecoration(
                  hintText: 'e.g. abc123def456',
                  prefixIcon: const Icon(Icons.tag, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Preview card
            if (_titleController.text.isNotEmpty || _bodyController.text.isNotEmpty) ...[
              Text(
                'Preview',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildNotificationPreview(isDark),
              const SizedBox(height: 24),
            ],

            // Send button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _sendNotification,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 20),
                label: Text(
                  _isSending ? 'Sending...' : 'Send Notification',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE50914).withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // App icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          // Title + Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KMM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                Text(
                  _titleController.text.isEmpty ? 'Notification Title' : _titleController.text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _bodyController.text.isEmpty ? 'Notification body text...' : _bodyController.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 64,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No notifications sent yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Compose and send your first notification',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final notification = NotificationModel.fromFirestore(docs[index]);
            return _buildNotificationHistoryItem(notification, isDark);
          },
        );
      },
    );
  }

  Widget _buildNotificationHistoryItem(NotificationModel notification, bool isDark) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: notification.isSent
                    ? Colors.green.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                notification.isSent ? Icons.check_circle : Icons.schedule,
                color: notification.isSent ? Colors.green : Colors.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: notification.isSent
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          notification.isSent ? 'SENT' : 'PENDING',
                          style: TextStyle(
                            color: notification.isSent ? Colors.green : Colors.orange,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Text(
                        notification.sentBy,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 12, color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Text(
                        notification.timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      if (notification.movieSlug != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.link, size: 12, color: const Color(0xFFE50914)),
                        const SizedBox(width: 4),
                        Text(
                          notification.movieSlug!,
                          style: const TextStyle(fontSize: 11, color: Color(0xFFE50914)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Delete button
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
              onPressed: () => _deleteNotification(notification.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}
