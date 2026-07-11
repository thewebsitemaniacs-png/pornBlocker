import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../blocking/presentation/providers/bypass_guard_provider.dart';
import '../../../chat/presentation/screens/supporters_list_screen.dart';
import '../../../chat/presentation/screens/supporter_inbox_screen.dart';
import 'app_blocker_settings_screen.dart';
import '../providers/habit_provider.dart';
import '../../domain/entities/habit_log.dart';
import '../providers/daily_inspiration_provider.dart';
import '../../domain/entities/daily_inspiration.dart';
import 'package:habit_breaker/features/auth/presentation/screens/paywall_screen.dart';

final permissionStatesFutureProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final channel = ref.read(platformChannelServiceProvider);
  final permissions = await channel.checkPermissions();
  return Map<String, bool>.from(permissions);
});

class DashboardTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

final dashboardTabIndexProvider = NotifierProvider<DashboardTabIndex, int>(DashboardTabIndex.new);

class HasConfessedToStranger extends Notifier<bool> {
  @override
  bool build() {
    final storage = ref.watch(storageServiceProvider);
    return storage.settingsBox.get('has_confessed_to_stranger', defaultValue: false) as bool;
  }

  void setConfessed() {
    state = true;
  }
}

final hasConfessedToStrangerProvider = NotifierProvider<HasConfessedToStranger, bool>(HasConfessedToStranger.new);

void _showPaywallBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: PaywallScreen(
          onUpgradeSuccess: () {
            Navigator.pop(context);
          },
        ),
      );
    },
  );
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessibilityState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityState();
    }
  }

  Future<void> _checkAccessibilityState() async {
    try {
      final channel = ref.read(platformChannelServiceProvider);
      final permissionsMap = await channel.checkPermissions();
      final currentAccessibility = permissionsMap['accessibility'] ?? false;
      final storage = ref.read(storageServiceProvider);
      
      final lastAccessibility = storage.settingsBox.get('last_accessibility_state', defaultValue: false) as bool;
      
      if (lastAccessibility && !currentAccessibility) {
        await ref.read(habitLogsProvider.notifier).addLog(
          'blocker_stopped',
          {
            'reason': 'Accessibility Service disabled by user in Settings',
            'action': 'accessibility_disabled',
          },
        );
      }
      
      await storage.settingsBox.put('last_accessibility_state', currentAccessibility);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isPremium = authState.profile?.isPremium ?? false;
    final username = authState.profile?.username ?? 'SleekPanda8276';
    final bypassState = ref.watch(bypassGuardProvider);
    final alerts = ref.watch(buddyNotificationProvider);
    final currentIndex = ref.watch(dashboardTabIndexProvider);

    if (bypassState.isLockoutActive && bypassState.lockoutUntil != null) {
      return LockoutOverlay(lockoutUntil: bypassState.lockoutUntil!);
    }

    final List<Widget> screens = [
      const _HabitTab(),
      const _BlockingTab(),
      const _BuddyTab(),
      const _AnalyticsTab(),
      const _ProfileTab(),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          appBar: AppBar(
            leading: (currentIndex == 0 || currentIndex == 3 || currentIndex == 4)
                ? Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: currentIndex == 4 ? const Color(0xFFE0F2FE) : const Color(0xFF4ED6C4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: currentIndex == 4
                          ? const Icon(
                              Icons.person,
                              color: Color(0xFF5D5F30),
                              size: 24,
                            )
                          : Image.asset(
                              'assets/images/mascot.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                    ),
                  )
                : null,
            title: currentIndex == 4
                ? Text(
                    username,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF5D5F30),
                      letterSpacing: -0.5,
                    ),
                  )
                : const SizedBox.shrink(),
            centerTitle: true,
            backgroundColor: const Color(0xFFF6F9FD),
            elevation: 0,
            actions: (currentIndex == 0 || currentIndex == 3 || currentIndex == 4)
                ? [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Color(0xFF5D5F30)),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No new notifications.'),
                            backgroundColor: Color(0xFF5AB2FF),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ]
                : [
                    if (isPremium)
                      IconButton(
                        icon: const Icon(Icons.cloud_sync, color: Color(0xFF5AB2FF)),
                        onPressed: () {
                          ref.read(habitTasksProvider.notifier).sync();
                          ref.read(habitLogsProvider.notifier).sync();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Synchronizing habits database with cloud...'),
                              backgroundColor: const Color(0xFF5AB2FF),
                              action: SnackBarAction(
                                label: 'Dismiss',
                                textColor: const Color(0xFF1E293B),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                  ],
          ),
          body: screens[currentIndex],
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: currentIndex,
            onTap: (index) {
              ref.read(dashboardTabIndexProvider.notifier).setIndex(index);
            },
          ),
        ),
        if (alerts.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _FloatingAlertBanner(alert: alerts.first),
          ),
      ],
    );
  }
}

// 15-Minute Full Screen Urge Lockout Screen
class LockoutOverlay extends StatefulWidget {
  final DateTime lockoutUntil;

  const LockoutOverlay({super.key, required this.lockoutUntil});

  @override
  State<LockoutOverlay> createState() => _LockoutOverlayState();
}

class _LockoutOverlayState extends State<LockoutOverlay> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    setState(() {
      _remaining = widget.lockoutUntil.difference(DateTime.now());
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withOpacity(0.2), width: 2),
                  ),
                  child: const Icon(Icons.lock_clock_outlined, size: 96, color: Colors.redAccent),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'URGE LOCKOUT ACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Addictive triggers hit repeatedly in a short window. App access is locked for 15 minutes to cool down and break the neural loop.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.5),
              ),
              const SizedBox(height: 48),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FB),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2EAF4)),
                  ),
                  child: Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 54,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Take a deep breath. Focus on your habit-replacement exercises.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// 1. Habit Engine View
class _HabitTab extends ConsumerWidget {
  const _HabitTab();

  String _formatLogMessage(HabitLog log) {
    final typeStr = log.eventType.replaceAll('_', ' ').toUpperCase();
    String message = typeStr;
    
    if (log.payload.containsKey('reason')) {
      message += ': ${log.payload['reason']}';
    } else if (log.payload.containsKey('title')) {
      message += ': "${log.payload['title']}"';
    } else if (log.payload.containsKey('matchedText')) {
      message += ': Blocked trigger keyword "${log.payload['matchedText']}"';
    } else if (log.payload.isNotEmpty) {
      final details = log.payload.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      message += ': $details';
    }
    return message;
  }

  Widget _buildChecklistCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildVerseOfTheDayCard(DailyInspiration inspiration, bool isCompleted) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFD200), // Gold Yellow
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Watermark Bible Icon
            Positioned(
              right: -10,
              bottom: -10,
              child: Opacity(
                opacity: 0.12,
                child: const Text('📖', style: TextStyle(fontSize: 80)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.auto_awesome, color: Color(0xFF5D5F30), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'VERSE OF THE DAY',
                            style: TextStyle(
                              color: Color(0xFF5D5F30),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.check, color: Color(0xFF5D5F30), size: 12),
                              SizedBox(width: 4),
                              Text(
                                'Read & Completed',
                                style: TextStyle(
                                  color: Color(0xFF5D5F30),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    inspiration.verse,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    inspiration.reference,
                    style: const TextStyle(
                      color: Color(0xFF5D5F30),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyConfessionsCard(DailyInspiration inspiration, bool isCompleted, VoidCallback? onComplete) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFC5F050), // Lime Green
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Watermark Shield Icon
            Positioned(
              right: -10,
              bottom: -10,
              child: Opacity(
                opacity: 0.12,
                child: const Text('🛡️', style: TextStyle(fontSize: 80)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.favorite_border, color: Color(0xFF1E293B), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'DAILY CONFESSIONS',
                            style: TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.check, color: Color(0xFF1E293B), size: 12),
                              SizedBox(width: 4),
                              Text(
                                'Read & Completed',
                                style: TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...inspiration.confessions.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildConfessionItem(c, isCompleted),
                      )),
                  if (!isCompleted && onComplete != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: onComplete,
                        icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                        label: const Text(
                          'Mark as Read & Completed',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfessionItem(String text, bool isCompleted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isCompleted ? Icons.check_circle : Icons.check_circle_outline,
          color: const Color(0xFF1E293B),
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthStreakCard(int currentStreak) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD200), // Gold Yellow
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Watermark Corn Icon
          Positioned(
            right: -10,
            bottom: -10,
            child: Opacity(
              opacity: 0.15,
              child: const Text('🌽', style: TextStyle(fontSize: 80)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Growth Streak',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              // Streaks Visual Row
              Row(
                children: List.generate(5, (index) {
                  final isFilled = index < currentStreak;
                  final hasDot = index == currentStreak && index < 5;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Container(
                      width: 22,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isFilled 
                            ? const Color(0xFF1E293B).withOpacity(0.15) 
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF1E293B).withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: hasDot 
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E293B),
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text(
                "You've been trigger free for $currentStreak day${currentStreak == 1 ? '' : 's'}!",
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLevelCard(AnalyticsState? analytics) {
    String levelName = 'Beginner';
    String description = 'Keep going to unlock focus milestones!';

    if (analytics != null) {
      final badgeOrder = [
        'Iron Will',
        'Consistency Master',
        'Obsidian Shield',
        'Bronze Shield',
        'First Step',
      ];
      for (final title in badgeOrder) {
        final badge = analytics.badges.firstWhere(
          (b) => b.title == title,
          orElse: () => BadgeAchievement(title: '', description: '', isUnlocked: false),
        );
        if (badge.title.isNotEmpty && badge.isUnlocked) {
          levelName = badge.title;
          description = badge.description;
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFC5F050), // Lime Green
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco, color: Color(0xFF1E293B), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  levelName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<HabitLog>> logsAsync,
  ) {
    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF5AB2FF).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.history, color: Color(0xFF5AB2FF), size: 24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No activity logged yet.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Start your journey by setting your first focus goal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.read(dashboardTabIndexProvider.notifier).setIndex(1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD200),
                    foregroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Start Now', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        final nonNullLogs = logs.whereType<HabitLog>().toList();
        final sortedLogs = nonNullLogs
          ..sort((HabitLog a, HabitLog b) => b.loggedAt.compareTo(a.loggedAt));
        final recentLogs = sortedLogs.take(3).toList();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2EAF4)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AllLogsScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...recentLogs.map((log) {
                    IconData icon = Icons.info_outline;
                    Color iconColor = const Color(0xFF5AB2FF);

                    if (log.eventType == 'block_triggered') {
                      icon = Icons.warning_amber_rounded;
                      iconColor = Colors.redAccent;
                    } else if (log.eventType == 'blocker_stopped') {
                      icon = Icons.block;
                      iconColor = Colors.redAccent;
                    } else if (log.eventType == 'task_completed') {
                      icon = Icons.check_circle_outline;
                      iconColor = Colors.green;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Icon(icon, color: iconColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatLogMessage(log),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            log.loggedAt.toLocal().toString().substring(11, 16),
                            style: TextStyle(
                              color: const Color(0xFF64748B).withOpacity(0.6),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const Divider(color: Color(0xFFE2EAF4)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'VIEW ALL LOGS',
                          style: TextStyle(
                            color: Color(0xFF5AB2FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, color: Color(0xFF5AB2FF), size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF5AB2FF))),
      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final username = authState.profile?.username ?? 'Anonymous Explorer';
    final hasPartner = authState.profile?.buddyId != null && authState.profile!.buddyId!.isNotEmpty;
    final hasConfessed = ref.watch(hasConfessedToStrangerProvider);

    final permissionsAsync = ref.watch(permissionStatesFutureProvider);
    final isBlockingActive = permissionsAsync.when(
      data: (p) => (p['accessibility'] ?? false) && (p['vpn_authorized'] ?? false) && (p['admin'] ?? false),
      error: (_, __) => false,
      loading: () => false,
    );

    final completedCount = (isBlockingActive ? 1 : 0) + (hasPartner ? 1 : 0) + (hasConfessed ? 1 : 0);
    final totalCount = 3;

    final logsAsync = ref.watch(habitLogsProvider);
    final analyticsAsync = ref.watch(analyticsProvider);
    final analytics = analyticsAsync.asData?.value;
    final currentStreak = analytics?.currentStreak ?? 0;

    final inspirationAsync = ref.watch(dailyInspirationProvider);
    final isInspirationCompleted = ref.watch(dailyInspirationStatusProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'WELCOME BACK, $username',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SETUP CHECKLIST',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  '$completedCount of $totalCount Complete',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D5F30),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (!isBlockingActive)
              _buildChecklistCard(
                context,
                title: 'Enable Content Block Engine',
                subtitle: 'Grant system permissions to secure your device',
                icon: Icons.shield,
                iconColor: const Color(0xFF10B981),
                bgColor: const Color(0xFFD1FAE5),
                onTap: () {
                  ref.read(dashboardTabIndexProvider.notifier).setIndex(1);
                },
              ),
            if (!hasPartner) ...[
              if (!isBlockingActive) const SizedBox(height: 8),
              _buildChecklistCard(
                context,
                title: 'Add an Accountability Partner',
                subtitle: 'Connect with a supporter to keep you focused',
                icon: Icons.people_outline,
                iconColor: const Color(0xFF3B82F6),
                bgColor: const Color(0xFFDBEAFE),
                onTap: () {
                  ref.read(dashboardTabIndexProvider.notifier).setIndex(2);
                },
              ),
            ],
            if (!hasConfessed) ...[
              if (!isBlockingActive || !hasPartner) const SizedBox(height: 8),
              _buildChecklistCard(
                context,
                title: 'Confess to a Stranger',
                subtitle: 'Share your struggles anonymously to get help',
                icon: Icons.chat_bubble_outline,
                iconColor: const Color(0xFFEC4899),
                bgColor: const Color(0xFFFCE7F3),
                onTap: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.settingsBox.put('has_confessed_to_stranger', true);
                  ref.read(hasConfessedToStrangerProvider.notifier).setConfessed();
                  await ref.read(platformChannelServiceProvider).openUrl('https://www.joshuasamuel.in/flee-chat');
                },
              ),
            ],
            if (isBlockingActive && hasPartner && hasConfessed)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ALL SHIELDS ACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047857),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your blocker and accountability systems are fully secure.',
                            style: TextStyle(color: const Color(0xFF047857).withOpacity(0.8), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            inspirationAsync.when(
              data: (inspiration) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVerseOfTheDayCard(inspiration, isInspirationCompleted),
                    const SizedBox(height: 24),
                    _buildDailyConfessionsCard(
                      inspiration,
                      isInspirationCompleted,
                      () => ref.read(dailyInspirationStatusProvider.notifier).markAsRead(inspiration),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              ),
              error: (err, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            _buildGrowthStreakCard(currentStreak),
            const SizedBox(height: 24),

            _buildLevelCard(analytics),
            const SizedBox(height: 24),

            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            _buildRecentActivitySection(context, ref, logsAsync),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(dashboardTabIndexProvider.notifier).setIndex(1);
        },
        backgroundColor: const Color(0xFFFFD200),
        foregroundColor: const Color(0xFF1E293B),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

class AllLogsScreen extends ConsumerWidget {
  const AllLogsScreen({super.key});

  String _formatLogMessage(HabitLog log) {
    final typeStr = log.eventType.replaceAll('_', ' ').toUpperCase();
    String message = typeStr;
    
    if (log.payload.containsKey('reason')) {
      message += ': ${log.payload['reason']}';
    } else if (log.payload.containsKey('title')) {
      message += ': "${log.payload['title']}"';
    } else if (log.payload.containsKey('matchedText')) {
      message += ': Blocked trigger keyword "${log.payload['matchedText']}"';
    } else if (log.payload.isNotEmpty) {
      final details = log.payload.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      message += ': $details';
    }
    return message;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(habitLogsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: const Text(
          'BEHAVIORAL HISTORY',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.5, color: const Color(0xFF1E293B)),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4F7FB),
        elevation: 0,
        iconTheme: const IconThemeData(color: const Color(0xFF1E293B)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: logsAsync.when(
          data: (logs) {
            if (logs.isEmpty) {
              return const Center(
                child: Text('No habit logs recorded yet.', style: TextStyle(color: Color(0xFF475569))),
              );
            }

            final nonNullLogs = logs.whereType<HabitLog>().toList();
            final sortedLogs = nonNullLogs
              ..sort((HabitLog a, HabitLog b) => b.loggedAt.compareTo(a.loggedAt));

            return ListView.builder(
              itemCount: sortedLogs.length,
              itemBuilder: (context, index) {
                final log = sortedLogs[index];
                IconData icon = Icons.info_outline;
                Color iconColor = const Color(0xFF5AB2FF);

                if (log.eventType == 'block_triggered') {
                  icon = Icons.warning_amber_rounded;
                  iconColor = Colors.redAccent;
                } else if (log.eventType == 'blocker_stopped') {
                  icon = Icons.block;
                  iconColor = Colors.redAccent;
                } else if (log.eventType == 'task_completed') {
                  icon = Icons.check_circle_outline;
                  iconColor = Colors.green;
                }

                return Card(
                  color: const Color(0xFFF4F7FB),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE2EAF4)),
                  ),
                  child: ListTile(
                    leading: Icon(icon, color: iconColor),
                    title: Text(
                      _formatLogMessage(log),
                      style: const TextStyle(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        log.loggedAt.toLocal().toString().substring(0, 19),
                        style: TextStyle(color: const Color(0xFF475569).withOpacity(0.5), fontSize: 11),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF5AB2FF))),
          error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
        ),
      ),
    );
  }
}

// 2. Native Blocking View
class _BlockingTab extends ConsumerStatefulWidget {
  const _BlockingTab();

  @override
  ConsumerState<_BlockingTab> createState() => _BlockingTabState();
}

class _BlockingTabState extends ConsumerState<_BlockingTab> {
  bool _isScreenBlockerEnabled = false;
  bool _isVpnEnabled = false;
  bool _isUninstallGuardEnabled = false;
  String? _bypassTargetFeature;
  
  Map<String, bool> _permissionStates = {
    'accessibility': false,
    'vpn_authorized': false,
    'vpn_running': false,
    'admin': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final storage = ref.read(storageServiceProvider);
      setState(() {
        _isScreenBlockerEnabled = storage.settingsBox.get('screen_blocker_enabled', defaultValue: false) as bool;
        _isVpnEnabled = storage.settingsBox.get('network_blocker_enabled', defaultValue: false) as bool;
        _isUninstallGuardEnabled = storage.settingsBox.get('uninstall_guard_enabled', defaultValue: false) as bool;
      });
      _checkCurrentPermissions();
    });
  }

  Future<void> _checkCurrentPermissions() async {
    try {
      final channel = ref.read(platformChannelServiceProvider);
      final permissionsMap = await channel.checkPermissions();
      
      final currentAccessibility = permissionsMap['accessibility'] ?? false;
      final isVpnAuthorized = permissionsMap['vpn_authorized'] ?? false;
      final isVpnRunning = permissionsMap['vpn_running'] ?? false;
      final isAdminActive = permissionsMap['admin'] ?? false;

      final storage = ref.read(storageServiceProvider);
      await storage.settingsBox.put('last_accessibility_state', currentAccessibility);

      // 1. Accessibility Scan Sync
      if (currentAccessibility && _isScreenBlockerEnabled) {
        await channel.setScreenBlockingEnabled(true);
      } else {
        await channel.setScreenBlockingEnabled(false);
      }

      // 2. VPN Service Sync
      if (isVpnAuthorized && _isVpnEnabled) {
        if (!isVpnRunning) {
          await channel.startBlocking();
          final blocklist = ref.read(blocklistProvider);
          await channel.updateBlocklist(blocklist.domains, blocklist.keywords);
        }
      } else {
        if (isVpnRunning) {
          await channel.stopBlocking();
        }
      }

      // 3. Uninstall Guard Sync
      if (isAdminActive && !_isUninstallGuardEnabled) {
        await channel.deactivateAdmin();
      }

      setState(() {
        _permissionStates = permissionsMap;
      });
    } catch (_) {}
  }

  Future<void> _requestSinglePermission(String type) async {
    try {
      final channel = ref.read(platformChannelServiceProvider);
      await channel.requestPermissions(type);
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        await _checkCurrentPermissions();
        final checkKey = type == 'vpn' ? 'vpn_authorized' : type;
        if (_permissionStates[checkKey] == true) {
          timer.cancel();
          
          final storage = ref.read(storageServiceProvider);
          // Automatically enable the toggle upon successful grant
          if (type == 'accessibility') {
            await storage.settingsBox.put('screen_blocker_enabled', true);
            setState(() => _isScreenBlockerEnabled = true);
            await channel.setScreenBlockingEnabled(true);
            ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Screen Blocker'});
          } else if (type == 'vpn') {
            await storage.settingsBox.put('network_blocker_enabled', true);
            setState(() => _isVpnEnabled = true);
            await channel.startBlocking();
            final blocklist = ref.read(blocklistProvider);
            await channel.updateBlocklist(blocklist.domains, blocklist.keywords);
            ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Network Blocker'});
          } else if (type == 'admin') {
            await storage.settingsBox.put('uninstall_guard_enabled', true);
            setState(() => _isUninstallGuardEnabled = true);
            ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Uninstall Guard'});
          }
          await _checkCurrentPermissions();
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleScreenBlocker(bool value) async {
    final storage = ref.read(storageServiceProvider);
    if (value) {
      if (_permissionStates['accessibility'] != true) {
        _requestSinglePermission('accessibility');
        return;
      }
      await storage.settingsBox.put('screen_blocker_enabled', true);
      setState(() => _isScreenBlockerEnabled = true);
      await ref.read(platformChannelServiceProvider).setScreenBlockingEnabled(true);
      ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Screen Blocker'});
    } else {
      setState(() {
        _bypassTargetFeature = 'accessibility';
      });
      ref.read(bypassGuardProvider.notifier).startBypassRequest(60);
    }
  }

  Future<void> _toggleUninstallGuard(bool value) async {
    final storage = ref.read(storageServiceProvider);
    if (value) {
      if (_permissionStates['admin'] != true) {
        _requestSinglePermission('admin');
        return;
      }
      await storage.settingsBox.put('uninstall_guard_enabled', true);
      setState(() => _isUninstallGuardEnabled = true);
      ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Uninstall Guard'});
    } else {
      await storage.settingsBox.put('uninstall_guard_enabled', false);
      setState(() => _isUninstallGuardEnabled = false);
      await ref.read(platformChannelServiceProvider).deactivateAdmin();
      ref.read(habitLogsProvider.notifier).addLog('blocker_stopped', {'feature': 'Uninstall Guard'});
    }
    await _checkCurrentPermissions();
  }

  Future<void> _toggleVpnBlocker(bool value) async {
    final storage = ref.read(storageServiceProvider);
    if (value) {
      if (_permissionStates['vpn_authorized'] != true) {
        _requestSinglePermission('vpn');
        return;
      }
      await storage.settingsBox.put('network_blocker_enabled', true);
      setState(() => _isVpnEnabled = true);
      final channel = ref.read(platformChannelServiceProvider);
      await channel.startBlocking();
      final blocklist = ref.read(blocklistProvider);
      await channel.updateBlocklist(blocklist.domains, blocklist.keywords);
      ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'feature': 'Network Blocker'});
    } else {
      setState(() {
        _bypassTargetFeature = 'vpn';
      });
      ref.read(bypassGuardProvider.notifier).startBypassRequest(60);
    }
    await _checkCurrentPermissions();
  }



  Widget _buildPermissionCard({
    required String numberAndTitle,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required bool isGranted,
    required VoidCallback onGrant,
    required bool isFeatureEnabled,
    required ValueChanged<bool> onFeatureToggled,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      numberAndTitle,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: isGranted
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isFeatureEnabled ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isFeatureEnabled ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isFeatureEnabled ? 'RUNNING & PROTECTING' : 'DISABLED',
                            style: TextStyle(
                              color: isFeatureEnabled ? const Color(0xFF047857) : const Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: isFeatureEnabled,
                        activeColor: const Color(0xFFFFD200),
                        activeTrackColor: const Color(0xFFFFD200).withOpacity(0.3),
                        onChanged: onFeatureToggled,
                      ),
                    ],
                  )
                : ElevatedButton(
                    onPressed: onGrant,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD200),
                      foregroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'GRANT PERMISSION',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bypassState = ref.watch(bypassGuardProvider);

    final isScreenActive = _permissionStates['accessibility'] == true && _isScreenBlockerEnabled;
    final isVpnActive = _permissionStates['vpn_running'] == true;
    final isProtectionActive = isScreenActive || isVpnActive;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Blocker Configuration',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Protect your focus by restricting distracting content.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),

            if (bypassState.isBypassRequested) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.shield_outlined, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'BYPASS DELAY ACTIVE',
                      style: TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Blocker disabling request starts a 60s cooldown. Take a deep breath.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${bypassState.bypassCountdownSeconds}s remaining',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            ref.read(bypassGuardProvider.notifier).cancelBypassRequest();
                            setState(() {
                              _bypassTargetFeature = null;
                            });
                          },
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF475569)),
                          child: const Text('Cancel Request'),
                        ),
                        if (bypassState.canConfirmBypass)
                          ElevatedButton(
                            onPressed: () async {
                              final storage = ref.read(storageServiceProvider);
                              final channel = ref.read(platformChannelServiceProvider);
                              
                              if (_bypassTargetFeature == 'accessibility') {
                                await storage.settingsBox.put('screen_blocker_enabled', false);
                                await channel.setScreenBlockingEnabled(false);
                                ref.read(habitLogsProvider.notifier).addLog('blocker_stopped', {'feature': 'Screen Blocker'});
                                setState(() {
                                  _isScreenBlockerEnabled = false;
                                  _bypassTargetFeature = null;
                                });
                              } else {
                                await storage.settingsBox.put('network_blocker_enabled', false);
                                await channel.stopBlocking();
                                ref.read(habitLogsProvider.notifier).addLog('blocker_stopped', {'feature': 'Network Blocker'});
                                setState(() {
                                  _isVpnEnabled = false;
                                  _bypassTargetFeature = null;
                                });
                              }
                              
                              ref.read(bypassGuardProvider.notifier).completeBypass();
                              await _checkCurrentPermissions();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            child: const Text('Confirm Turn Off', style: TextStyle(color: Color(0xFF1E293B))),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isProtectionActive ? const Color(0xFF10B981).withOpacity(0.5) : const Color(0xFFE2EAF4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Blocker Protection Status',
                      style: TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          isProtectionActive ? Icons.check_circle : Icons.radio_button_off,
                          color: isProtectionActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isProtectionActive ? 'PROTECTION ACTIVE' : 'NO ACTIVE PROTECTION',
                          style: TextStyle(
                            color: isProtectionActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Enable individual features below. You no longer need all permissions to activate blocker modules.',
                        style: TextStyle(color: Color(0xFF0369A1), fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),

            Row(
              children: const [
                Icon(Icons.verified_user_outlined, color: Color(0xFF5D5F30), size: 18),
                SizedBox(width: 8),
                Text(
                  'SYSTEM PERMISSIONS REQUIRED',
                  style: TextStyle(
                    color: Color(0xFF5D5F30),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'flee needs system-level services to scan content and filter network DNS queries to ensure your focus stays protected.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            _buildPermissionCard(
              numberAndTitle: '1. Accessibility Service',
              description: 'Scans screen layouts for keyword blocks and UI prevention.',
              icon: Icons.accessibility_new_rounded,
              iconColor: const Color(0xFFB58A00),
              iconBgColor: const Color(0xFFFEF3C7),
              isGranted: _permissionStates['accessibility'] ?? false,
              onGrant: () => _requestSinglePermission('accessibility'),
              isFeatureEnabled: _isScreenBlockerEnabled,
              onFeatureToggled: (val) => _toggleScreenBlocker(val),
            ),
            const SizedBox(height: 16),
            _buildPermissionCard(
              numberAndTitle: '2. Local VPN Connection',
              description: 'Enforces DNS sinkholes on domain blocks at the system level.',
              icon: Icons.vpn_lock_rounded,
              iconColor: const Color(0xFF047857),
              iconBgColor: const Color(0xFFD1FAE5),
              isGranted: _permissionStates['vpn_authorized'] ?? false,
              onGrant: () => _requestSinglePermission('vpn'),
              isFeatureEnabled: _isVpnEnabled,
              onFeatureToggled: (val) => _toggleVpnBlocker(val),
            ),
            const SizedBox(height: 16),
            _buildPermissionCard(
              numberAndTitle: '3. Device Administrator',
              description: 'Uninstall prevention guard to keep your habits consistent.',
              icon: Icons.admin_panel_settings_rounded,
              iconColor: const Color(0xFF0369A1),
              iconBgColor: const Color(0xFFDBEAFE),
              isGranted: _permissionStates['admin'] ?? false,
              onGrant: () => _requestSinglePermission('admin'),
              isFeatureEnabled: _isUninstallGuardEnabled,
              onFeatureToggled: (val) => _toggleUninstallGuard(val),
            ),
            const SizedBox(height: 28),

            ElevatedButton.icon(
              onPressed: () {
                _checkCurrentPermissions();
                ref.read(blocklistProvider.notifier).fetchAndSync();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Sync Configurations'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2EAF4),
                foregroundColor: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// 3. Anonymous Profile Tab
class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? const Color(0xFFE2EAF4),
          width: borderColor != null ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: textColor ?? const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(0xFF94A3B8),
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final username = authState.profile?.username ?? 'SleekPanda8276';
    final isPremium = authState.profile?.isPremium ?? false;


    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFFFD200), width: 4),
                    left: BorderSide(color: Color(0xFFE2EAF4)),
                    right: BorderSide(color: Color(0xFFE2EAF4)),
                    bottom: BorderSide(color: Color(0xFFE2EAF4)),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE0F2FE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 40,
                            color: Color(0xFF5D5F30),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF4D5E2A),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.lock_outline, size: 13, color: Color(0xFF64748B)),
                          SizedBox(width: 6),
                          Text(
                            '100% Anonymous Profiling',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFFE2EAF4), height: 1),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Account Tier:',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isPremium ? 'PREMIUM SUBSCRIBER' : 'FREE TIER',
                          style: TextStyle(
                            color: isPremium ? const Color(0xFFB45309) : const Color(0xFF64748B),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),


            if (isPremium)
              _buildSettingsCard(
                context: context,
                title: 'Force Cloud Sync Now',
                icon: Icons.cloud_sync,
                iconBg: const Color(0xFFF0F9FF),
                iconColor: const Color(0xFF0284C7),
                onTap: () async {
                  try {
                    await ref.read(habitTasksProvider.notifier).sync();
                    await ref.read(habitLogsProvider.notifier).sync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Sync successful!'),
                          backgroundColor: Colors.green,
                          action: SnackBarAction(
                            label: 'Dismiss',
                            textColor: const Color(0xFF1E293B),
                            onPressed: () {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            },
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Sync failed. Please check connection.'),
                          backgroundColor: Colors.redAccent,
                          action: SnackBarAction(
                            label: 'Dismiss',
                            textColor: const Color(0xFF1E293B),
                            onPressed: () {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            },
                          ),
                        ),
                      );
                    }
                  }
                },
              ),



            _buildSettingsCard(
              context: context,
              title: 'Confess to a Stranger',
              icon: Icons.chat_bubble_outline,
              iconBg: const Color(0xFFFCE7F3),
              iconColor: const Color(0xFFEC4899),
              onTap: () async {
                final storage = ref.read(storageServiceProvider);
                await storage.settingsBox.put('has_confessed_to_stranger', true);
                ref.read(hasConfessedToStrangerProvider.notifier).setConfessed();
                await ref.read(platformChannelServiceProvider).openUrl('https://www.joshuasamuel.in/flee-chat');
              },
            ),

            _buildSettingsCard(
              context: context,
              title: 'App Guard Settings',
              icon: Icons.shield_outlined,
              iconBg: const Color(0xFFF0F9FF),
              iconColor: const Color(0xFF0284C7),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AppBlockerSettingsScreen(),
                  ),
                );
              },
            ),

            _buildSettingsCard(
              context: context,
              title: 'Sign Out of Application',
              icon: Icons.logout,
              iconBg: const Color(0xFFF0F9FF),
              iconColor: const Color(0xFF0284C7),
              onTap: () {
                ref.read(authProvider.notifier).signOut();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;

  DashedBorderPainter({
    this.color = const Color(0xFFCBD5E1),
    this.strokeWidth = 1.0,
    this.gap = 4.0,
    this.dash = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;
    final double r = 16.0;

    _drawDashedLine(canvas, Offset(r, 0), Offset(w - r, 0), paint);
    _drawDashedLine(canvas, Offset(w, r), Offset(w, h - r), paint);
    _drawDashedLine(canvas, Offset(w - r, h), Offset(r, h), paint);
    _drawDashedLine(canvas, Offset(0, h - r), Offset(0, r), paint);

    final rectTopLeft = Rect.fromLTWH(0, 0, r * 2, r * 2);
    canvas.drawArc(rectTopLeft, 3.14, 1.57, false, paint);

    final rectTopRight = Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2);
    canvas.drawArc(rectTopRight, 4.71, 1.57, false, paint);

    final rectBottomRight = Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2);
    canvas.drawArc(rectBottomRight, 0, 1.57, false, paint);

    final rectBottomLeft = Rect.fromLTWH(0, h - r * 2, r * 2, r * 2);
    canvas.drawArc(rectBottomLeft, 1.57, 1.57, false, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final double totalDistance = (end - start).distance;
    final double dashCount = (totalDistance / (dash + gap)).floorToDouble();
    final Offset direction = (end - start) / totalDistance;

    for (double i = 0; i < dashCount; i++) {
      final double startDist = i * (dash + gap);
      final double endDist = startDist + dash;
      canvas.drawLine(
        start + direction * startDist,
        start + direction * endDist,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BuddyTab extends ConsumerStatefulWidget {
  const _BuddyTab();

  @override
  ConsumerState<_BuddyTab> createState() => _BuddyTabState();
}

class _BuddyTabState extends ConsumerState<_BuddyTab> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  UserProfile? _searchResult;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResult = null;
      _searchError = null;
    });

    final authNotifier = ref.read(authProvider.notifier);
    final result = await authNotifier.searchBuddy(query);

    setState(() {
      _isSearching = false;
      if (result != null) {
        _searchResult = result;
      } else {
        _searchError = 'User not found. Check spelling of their username.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentProfile = authState.profile;
    final linkedPartnersAsync = ref.watch(linkedPartnersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Accountability',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Manage your partners and see who's keeping you on track.",
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'YOUR ACCOUNTABILITY BUDDY',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),

            if (currentProfile?.buddyId != null && currentProfile!.buddyId!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EAF4)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      top: -10,
                      child: Opacity(
                        opacity: 0.05,
                        child: const Icon(
                          Icons.shield,
                          size: 100,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFF7ED),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Linked Accountability Partner',
                                    style: TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Your habit logs are visible to this buddy.',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () {
                              ref.read(authProvider.notifier).unlinkBuddy();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'UNLINK',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EAF4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add a Buddy to keep you accountable. Search by their anonymous username:',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2EAF4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Search Username (e.g. CalmEagle2019)',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: _isSearching
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFFFD200),
                                    ),
                                  )
                                : const Icon(Icons.search, color: Color(0xFFFFD200)),
                            onPressed: _performSearch,
                          ),
                        ],
                      ),
                    ),
                    if (_searchError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _searchError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                    if (_searchResult != null) ...[
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFE2EAF4)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _searchResult!.username,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ref.read(authProvider.notifier).linkBuddy(_searchResult!.id);
                              setState(() {
                                _searchResult = null;
                                _searchController.clear();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD200),
                              foregroundColor: const Color(0xFF1E293B),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('LINK BUDDY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 32),

            const Text(
              'PARTNERS YOU ARE OVERSEEING',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),

            linkedPartnersAsync.when(
              data: (partners) {
                if (partners.isEmpty) {
                  return CustomPaint(
                    painter: DashedBorderPainter(color: const Color(0xFFE2EAF4), strokeWidth: 1.5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE0F2FE),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.person_off_outlined, color: Color(0xFF0284C7), size: 24),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No users have linked you as their buddy yet. Ask them to search for your username on their app!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              final currentProfile = ref.read(authProvider).profile;
                              if (currentProfile != null && currentProfile.username.isNotEmpty) {
                                Clipboard.setData(ClipboardData(text: currentProfile.username));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Username "${currentProfile.username}" copied to clipboard! Share it with your friends.'),
                                    backgroundColor: const Color(0xFF5AB2FF),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Invite Friends', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4D5E2A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: partners.length,
                  itemBuilder: (context, index) {
                    final partner = partners[index];
                    return _PartnerLogTile(partner: partner);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF5AB2FF))),
              error: (err, _) => Center(child: Text('Error loading partners: $err', style: const TextStyle(color: Colors.red))),
            ),

            const SizedBox(height: 36),
            Center(
              child: Opacity(
                opacity: 0.85,
                child: Image.asset(
                  'assets/images/mascot.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _PartnerLogTile extends ConsumerStatefulWidget {
  final UserProfile partner;

  const _PartnerLogTile({required this.partner});

  @override
  ConsumerState<_PartnerLogTile> createState() => _PartnerLogTileState();
}

class _PartnerLogTileState extends ConsumerState<_PartnerLogTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(widget.partner.username, style: const TextStyle(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold)),
            subtitle: const Text('Linked Partner', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
            trailing: Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: const Color(0xFFFFD200),
            ),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
          ),
          if (_isExpanded) ...[
            const Divider(color: Color(0xFFE2EAF4), height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer(
                builder: (context, ref, child) {
                  final logsAsync = ref.watch(partnerLogsProvider(widget.partner.id));

                  return logsAsync.when(
                    data: (logs) {
                      if (logs.isEmpty) {
                        return const Text('No log entries registered.', style: TextStyle(color: Color(0xFF475569), fontSize: 12));
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logs.length > 5 ? 5 : logs.length,
                        itemBuilder: (context, logIndex) {
                          final log = logs[logIndex];
                          final isBlock = log.eventType == 'block_triggered' || log.eventType == 'blocker_stopped';
                          final icon = isBlock ? Icons.warning_amber_rounded : Icons.info_outline;
                          final iconColor = isBlock ? Colors.redAccent : const Color(0xFF5AB2FF);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Icon(icon, size: 14, color: iconColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${log.eventType.replaceAll('_', ' ').toUpperCase()}: ${log.payload['title'] ?? log.payload['status'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: const Color(0xFF475569), fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '${log.loggedAt.hour}:${log.loggedAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5AB2FF)))),
                    error: (err, _) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FloatingAlertBanner extends ConsumerWidget {
  final BuddyAlert alert;

  const _FloatingAlertBanner({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ALERT: ${alert.partnerName}',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    style: const TextStyle(color: const Color(0xFF1E293B), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: const Color(0xFF475569), size: 18),
              onPressed: () {
                ref.read(buddyNotificationProvider.notifier).dismissAlert(alert.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab();

  String _toDateString(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return analyticsAsync.when(
      data: (data) => Scaffold(
        backgroundColor: const Color(0xFFF6F9FD),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStreakSection(data),
              const SizedBox(height: 20),
              _buildHeatmapSection(data),
              const SizedBox(height: 20),
              _buildUrgesChartSection(data),
              const SizedBox(height: 20),
              _buildBadgesSection(data),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF5AB2FF))),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error loading analytics: $err', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

  Widget _buildStreakCard({
    required String title,
    required String days,
    required Color circleColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            days,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakSection(AnalyticsState data) {
    return Row(
      children: [
        Expanded(
          child: _buildStreakCard(
            title: 'Current Streak',
            days: '${data.currentStreak} DAYS',
            circleColor: const Color(0xFFC5F050),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStreakCard(
            title: 'Longest Streak',
            days: '${data.longestStreak} DAYS',
            circleColor: const Color(0xFFFFD200),
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmapSection(AnalyticsState data) {
    final days = <DateTime>[];
    final today = DateTime.now();
    for (int i = 34; i >= 0; i--) {
      days.add(today.subtract(Duration(days: i)));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '35-DAY FOCUS CALENDAR',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              final dateStr = _toDateString(date);
              
              Color cellColor = const Color(0xFFE0F2FE);
              Widget? cellChild;
              String tooltip = "No activity recorded";

              if (data.violationDays.contains(dateStr)) {
                cellColor = const Color(0xFFEF4444);
                tooltip = "Urge recorded";
              } else if (data.cleanDays.contains(dateStr)) {
                cellColor = const Color(0xFF4D5E2A);
                cellChild = const Icon(Icons.check, color: Colors.white, size: 14);
                tooltip = "Clean day focus maintained";
              }

              return Tooltip(
                message: "${date.day}/${date.month} - $tooltip",
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cellColor == const Color(0xFFE0F2FE)
                          ? const Color(0xFFD0E3F3)
                          : Colors.transparent,
                    ),
                  ),
                  child: cellChild,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _ColorLegendItem(color: Color(0xFFE0F2FE), label: 'Inactive'),
              SizedBox(width: 16),
              _ColorLegendItem(color: Color(0xFF4D5E2A), label: 'Clean'),
              SizedBox(width: 16),
              _ColorLegendItem(color: Color(0xFFEF4444), label: 'Triggered'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrgesChartSection(AnalyticsState data) {
    int night = 0;
    int morning = 0;
    int afternoon = 0;
    int evening = 0;

    data.hourlyUrgeDistribution.forEach((hour, count) {
      if (hour >= 0 && hour < 6) night += count;
      else if (hour >= 6 && hour < 12) morning += count;
      else if (hour >= 12 && hour < 18) afternoon += count;
      else if (hour >= 18 && hour < 24) evening += count;
    });

    final total = night + morning + afternoon + evening;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'URGES BY TIME OF DAY',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BarWidget(label: 'Night\n(12am-6am)', count: night, total: total),
              _BarWidget(label: 'Morning\n(6am-12pm)', count: morning, total: total),
              _BarWidget(label: 'Afternoon\n(12pm-6pm)', count: afternoon, total: total),
              _BarWidget(label: 'Evening\n(6pm-12am)', count: evening, total: total),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesSection(AnalyticsState data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FOCUS MILESTONES & BADGES',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: data.badges.length,
            itemBuilder: (context, index) {
              final badge = data.badges[index];
              final Color cardColor = badge.isUnlocked ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC);
              final Color accentColor = badge.isUnlocked ? const Color(0xFF0284C7) : const Color(0xFF94A3B8);

              IconData badgeIcon = Icons.lock_outline;
              if (badge.isUnlocked) {
                if (badge.title.contains('Step')) badgeIcon = Icons.directions_walk_rounded;
                else if (badge.title.contains('Bronze')) badgeIcon = Icons.shield_outlined;
                else if (badge.title.contains('Obsidian')) badgeIcon = Icons.shield;
                else if (badge.title.contains('Consistency')) badgeIcon = Icons.verified_rounded;
                else if (badge.title.contains('Champion')) badgeIcon = Icons.emoji_events;
                else badgeIcon = Icons.military_tech_rounded;
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: badge.isUnlocked ? const Color(0xFF0284C7).withOpacity(0.3) : const Color(0xFFE2EAF4),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(badgeIcon, color: accentColor, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      badge.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badge.isUnlocked ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badge.isUnlocked ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ColorLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _ColorLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color == const Color(0xFFFFFFFF) ? const Color(0xFFE2EAF4) : Colors.transparent),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFF475569), fontSize: 11)),
      ],
    );
  }
}

class _BarWidget extends StatelessWidget {
  final String label;
  final int count;
  final int total;

  const _BarWidget({required this.label, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final double percent = total > 0 ? count / total : 0.0;
    final double barHeight = 100 * percent;

    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: count > 0 ? const Color(0xFF5AB2FF) : const Color(0xFFCBD5E1),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 32,
          height: 100,
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2EAF4)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 32,
            height: barHeight == 0 ? 4 : barHeight,
            decoration: BoxDecoration(
              color: barHeight == 0 ? const Color(0xFFEDF2F7) : const Color(0xFF5AB2FF),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF475569), fontSize: 10),
        ),
      ],
    );
  }
}

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavBarItemData(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      ),
      _NavBarItemData(
        icon: Icons.shield_outlined,
        activeIcon: Icons.shield,
        label: 'Blocker',
      ),
      _NavBarItemData(
        icon: Icons.psychology_outlined,
        activeIcon: Icons.psychology,
        label: 'Buddy',
      ),
      _NavBarItemData(
        icon: Icons.bar_chart_rounded,
        activeIcon: Icons.bar_chart_rounded,
        label: 'Analytics',
      ),
      _NavBarItemData(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
      ),
    ];

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = currentIndex == index;
          final item = items[index];

          if (isSelected) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.activeIcon,
                    color: const Color(0xFF5D5F30),
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: Color(0xFF5D5F30),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          } else {
            return InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      color: const Color(0xFF5D5F30),
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: Color(0xFF5D5F30),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }),
      ),
    );
  }
}

class _NavBarItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _NavBarItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}


