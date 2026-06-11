import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for push notifications stored in Firestore `notifications` collection.
///
/// When an admin sends a notification, it is saved to Firestore.
/// A Cloud Function then triggers on the new document and sends FCM push
/// to the `movies_all` topic. This model represents the Firestore document schema.
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String? movieId;
  final String? movieSlug;
  final String? imageUrl;
  final String sentBy;
  final DateTime sentAt;
  final bool isSent; // Whether FCM push was successfully sent
  final int? recipientCount; // Number of devices that received the push

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.movieId,
    this.movieSlug,
    this.imageUrl,
    required this.sentBy,
    required this.sentAt,
    this.isSent = false,
    this.recipientCount,
  });

  /// Create from Firestore document
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      movieId: data['movieId'],
      movieSlug: data['movieSlug'],
      imageUrl: data['imageUrl'],
      sentBy: data['sentBy'] ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSent: data['isSent'] ?? false,
      recipientCount: data['recipientCount'],
    );
  }

  /// Convert to Firestore document data
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      'movieId': movieId,
      'movieSlug': movieSlug,
      'imageUrl': imageUrl,
      'sentBy': sentBy,
      'sentAt': FieldValue.serverTimestamp(),
      'isSent': isSent,
      'recipientCount': recipientCount,
    };
  }

  /// Time ago string for display
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(sentAt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${sentAt.day}/${sentAt.month}/${sentAt.year}';
  }
}
