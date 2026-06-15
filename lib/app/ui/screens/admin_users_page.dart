import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:provider/provider.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore.collection('users').orderBy('createdAt', descending: true).get();
      final users = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'username': data['username'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'isAdmin': data['isAdmin'] == true || data['isAdmin'] == 'true',
          'isVip': data['isVip'] == true || data['isVip'] == 'true',
          'isBanned': data['isBanned'] == true,
          'registrationDate': data['registrationDate'] ?? '',
          'oneSignalPlayerId': data['oneSignalPlayerId'] ?? '',
        };
      }).toList();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final query = _searchQuery.toLowerCase();
    return _users.where((u) {
      final username = (u['username'] as String).toLowerCase();
      final email = (u['email'] as String).toLowerCase();
      return username.contains(query) || email.contains(query);
    }).toList();
  }

  Future<void> _toggleBan(String uid, bool currentlyBanned) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isBanned': !currentlyBanned,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentlyBanned ? 'User unbanned' : 'User banned'),
          backgroundColor: currentlyBanned ? Colors.green : Colors.redAccent,
        ),
      );
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _forceLogout(String uid) async {
    // Clear the user's logged_in_devices so they need to re-login
    try {
      await _firestore.collection('users').doc(uid).update({
        'logged_in_devices': [],
        'forceLogout': true,
        'forceLogoutAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Force logout initiated. User will be logged out on next app open.'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _changeRole(String uid, String currentRole) async {
    final newRole = currentRole == 'admin' ? 'user' : 'admin';
    try {
      await _firestore.collection('users').doc(uid).update({
        'isAdmin': newRole == 'admin',
        'role': newRole,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Role changed to $newRole'),
          backgroundColor: Colors.green,
        ),
      );
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appConfig = Provider.of<AppConfig>(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.languageCode == 'my' ? 'အသုံးပြုသူများ' : 'Users'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: appConfig.languageCode == 'my' ? 'အသုံးပြုသူ ရှာဖွေရန်...' : 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatChip('Total: ${_users.length}', const Color(0xFF2196F3)),
                const SizedBox(width: 8),
                _buildStatChip('Admins: ${_users.where((u) => u['isAdmin'] == true).length}', const Color(0xFFFF9800)),
                const SizedBox(width: 8),
                _buildStatChip('Banned: ${_users.where((u) => u['isBanned'] == true).length}', Colors.redAccent),
                const SizedBox(width: 8),
                _buildStatChip('VIP: ${_users.where((u) => u['isVip'] == true).length}', const Color(0xFFFFD700)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Users list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          appConfig.languageCode == 'my' ? 'အသုံးပြုသူ မရှိပါ' : 'No users found',
                          style: theme.textTheme.bodyLarge,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadUsers,
                        color: const Color(0xFFE50914),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            return _buildUserCard(user, theme, isDark, appConfig);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, ThemeData theme, bool isDark, AppConfig appConfig) {
    final uid = user['uid'] as String;
    final username = user['username'] as String;
    final email = user['email'] as String;
    final isAdmin = user['isAdmin'] as bool;
    final isVip = user['isVip'] as bool;
    final isBanned = user['isBanned'] as bool;
    final regDate = user['registrationDate'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBanned
            ? const BorderSide(color: Colors.redAccent, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: username + badges
            Row(
              children: [
                // Avatar circle
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isBanned
                      ? Colors.redAccent.withOpacity(0.2)
                      : const Color(0xFFE50914).withOpacity(0.15),
                  child: Text(
                    username[0].toUpperCase(),
                    style: TextStyle(
                      color: isBanned ? Colors.redAccent : const Color(0xFFE50914),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              username,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isBanned ? Colors.grey : null,
                                decoration: isBanned ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isAdmin)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Admin', style: TextStyle(color: Color(0xFFFF9800), fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          if (isVip)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('VIP', style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          if (isBanned)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Banned', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Registration date
            if (regDate.isNotEmpty)
              Text(
                '${appConfig.languageCode == 'my' ? 'မှတ်ပုံတင်ရက်' : 'Registered'}: $regDate',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
              ),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Role change button (Admin ↔ User)
                if (!isAdmin || uid != FirebaseAuth.instance.currentUser?.uid)
                  TextButton.icon(
                    onPressed: () => _changeRole(uid, isAdmin ? 'admin' : 'user'),
                    icon: Icon(isAdmin ? Icons.person_outline : Icons.admin_panel_settings_outlined, size: 16),
                    label: Text(isAdmin ? 'Make User' : 'Make Admin', style: const TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9800),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),

                const SizedBox(width: 4),

                // Force Logout button
                TextButton.icon(
                  onPressed: () => _forceLogout(uid),
                  icon: const Icon(Icons.logout, size: 16),
                  label: Text(appConfig.languageCode == 'my' ? 'အတင်းထွက်' : 'Force Logout', style: const TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),

                const SizedBox(width: 4),

                // Ban/Unban button
                TextButton.icon(
                  onPressed: () => _toggleBan(uid, isBanned),
                  icon: Icon(isBanned ? Icons.check_circle_outline : Icons.block, size: 16),
                  label: Text(isBanned ? 'Unban' : 'Ban', style: const TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: isBanned ? Colors.green : Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
