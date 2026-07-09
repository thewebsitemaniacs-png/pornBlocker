import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import 'chat_room_screen.dart';

class SupporterInboxScreen extends ConsumerWidget {
  const SupporterInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChatsAsync = ref.watch(activeChatsProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: const Text(
          'SUPPORTER CHAT INBOX',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: const Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4F7FB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: const Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: activeChatsAsync.when(
        data: (chats) {
          if (chats.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Your inbox is empty. Client confessions will appear here when they send you messages.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF475569), fontSize: 14),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chatPartner = chats[index];
              final unreadCount = unreadCounts[chatPartner.id] ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: unreadCount > 0 ? const Color(0xFF5AB2FF) : const Color(0xFFE2EAF4),
                    width: unreadCount > 0 ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: unreadCount > 0
                        ? const Color(0xFF5AB2FF).withOpacity(0.2)
                        : const Color(0xFFE2EAF4),
                    child: Icon(
                      Icons.person_outline,
                      color: unreadCount > 0 ? const Color(0xFF5AB2FF) : const Color(0xFF475569),
                    ),
                  ),
                  title: Text(
                    chatPartner.username,
                    style: const TextStyle(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Anonymous Client Message',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: const Color(0xFF1E293B),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(partner: chatPartner),
                      ),
                    ).then((_) {
                      ref.invalidate(activeChatsProvider);
                    });
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF5AB2FF))),
        error: (err, _) => Center(
          child: Text('Error loading inbox: $err', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }
}
