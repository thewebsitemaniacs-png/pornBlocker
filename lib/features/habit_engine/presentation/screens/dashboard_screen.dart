import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../blocking/presentation/providers/bypass_guard_provider.dart';
import '../../../chat/presentation/screens/supporters_list_screen.dart';
import '../../../chat/presentation/screens/supporter_inbox_screen.dart';
import 'app_blocker_settings_screen.dart';
import '../providers/habit_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

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
    final bypassState = ref.watch(bypassGuardProvider);
    final alerts = ref.watch(buddyNotificationProvider);

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
          backgroundColor: const Color(0xFF0F0E17),
          appBar: AppBar(
            title: Text(
              _currentIndex == 0
                  ? 'HABIT ENGINE'
                  : _currentIndex == 1
                      ? 'NATIVE BLOCKER'
                      : _currentIndex == 2
                          ? 'ACCOUNTABILITY'
                          : _currentIndex == 3
                              ? 'OBSIDIAN ANALYTICS'
                              : 'ANONYMOUS PROFILE',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
            backgroundColor: const Color(0xFF1F1E29),
            elevation: 0,
            actions: [
              if (isPremium)
                IconButton(
                  icon: const Icon(Icons.cloud_sync, color: Color(0xFFFF8906)),
                  onPressed: () {
                    ref.read(habitTasksProvider.notifier).sync();
                    ref.read(habitLogsProvider.notifier).sync();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Synchronizing habits database with cloud...'),
                        backgroundColor: const Color(0xFFFF8906),
                        action: SnackBarAction(
                          label: 'Dismiss',
                          textColor: Colors.white,
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
          body: screens[_currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: const Color(0xFF1F1E29),
            selectedItemColor: const Color(0xFFFF8906),
            unselectedItemColor: const Color(0xFFA7A9BE),
            showSelectedLabels: true,
            showUnselectedLabels: false,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.psychology_outlined),
                activeIcon: Icon(Icons.psychology),
                label: 'Habits',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.block_flipped),
                activeIcon: Icon(Icons.block),
                label: 'Blocker',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Buddy',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.analytics_outlined),
                activeIcon: Icon(Icons.analytics),
                label: 'Analytics',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.fingerprint),
                activeIcon: Icon(Icons.fingerprint_rounded),
                label: 'Profile',
              ),
            ],
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
      backgroundColor: const Color(0xFF0F0E17),
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
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Addictive triggers hit repeatedly in a short window. App access is locked for 15 minutes to cool down and break the neural loop.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFFA7A9BE), height: 1.5),
              ),
              const SizedBox(height: 48),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1E29),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF2E2F3E)),
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
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFFA7A9BE)),
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

  void _showAddTaskDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1E29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'New Behavioral Task',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Task Title',
                  labelStyle: const TextStyle(color: Color(0xFFA7A9BE)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: const Color(0xFFFF8906).withOpacity(0.3)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFF8906)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Cognitive Strategy / Notes',
                  labelStyle: const TextStyle(color: Color(0xFFA7A9BE)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: const Color(0xFFFF8906).withOpacity(0.3)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFF8906)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Color(0xFFA7A9BE))),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                final desc = descController.text.trim();
                if (title.isNotEmpty) {
                  ref.read(habitTasksProvider.notifier).addTask(title, desc.isEmpty ? null : desc);
                  ref.read(habitLogsProvider.notifier).addLog(
                    'task_created',
                    {'title': title},
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8906),
                foregroundColor: const Color(0xFF0F0E17),
              ),
              child: const Text('ADD'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(habitTasksProvider);
    final logsAsync = ref.watch(habitLogsProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFFF8906)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8906).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Cognitive Tracker',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Perform habit-replacement activities to rewire urges and break mental loops.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddTaskDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log Urge Control Exercise'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F0E17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'BEHAVIORAL TASKS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA7A9BE),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 2,
            child: tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return Center(
                    child: Text(
                      'No tasks created. Click above to log your first urge strategy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: const Color(0xFFA7A9BE).withOpacity(0.6)),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return Card(
                      color: const Color(0xFF1F1E29),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: task.synced
                              ? Colors.green.withOpacity(0.2)
                              : Colors.orange.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Checkbox(
                          value: task.isCompleted,
                          activeColor: const Color(0xFFFF8906),
                          checkColor: const Color(0xFF0F0E17),
                          side: const BorderSide(color: Color(0xFFA7A9BE)),
                          onChanged: (_) {
                            ref.read(habitTasksProvider.notifier).toggleTaskCompletion(task.id);
                            ref.read(habitLogsProvider.notifier).addLog(
                              'task_toggled',
                              {'id': task.id, 'title': task.title, 'completed': !task.isCompleted},
                            );
                          },
                        ),
                        title: Text(
                          task.title,
                          style: TextStyle(
                            color: Colors.white,
                            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: task.description != null
                            ? Text(
                                task.description!,
                                style: TextStyle(
                                  color: const Color(0xFFA7A9BE),
                                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              task.synced ? Icons.cloud_done : Icons.cloud_off,
                              size: 16,
                              color: task.synced ? Colors.green : Colors.orange,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                ref.read(habitTasksProvider.notifier).deleteTask(task.id);
                                ref.read(habitLogsProvider.notifier).addLog(
                                  'task_deleted',
                                  {'id': task.id, 'title': task.title},
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
              error: (err, _) => Center(child: Text('Error loading tasks: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'BEHAVIORAL EVENT LOGS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA7A9BE),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 1,
            child: logsAsync.when(
              data: (logs) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No event history logged yet.',
                      style: TextStyle(color: Color(0xFFA7A9BE)),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    IconData icon = Icons.info_outline;
                    Color iconColor = const Color(0xFFFF8906);

                    if (log.eventType == 'block_triggered') {
                      icon = Icons.warning_amber_rounded;
                      iconColor = Colors.redAccent;
                    } else if (log.eventType == 'task_toggled') {
                      icon = Icons.check_circle_outline;
                      iconColor = Colors.green;
                    } else if (log.eventType == 'urge_overcome') {
                      icon = Icons.star_border_rounded;
                      iconColor = Colors.teal;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: iconColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${log.eventType.replaceAll('_', ' ').toUpperCase()}: ${log.payload['title'] ?? log.payload['id'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                          Text(
                            '${log.loggedAt.hour}:${log.loggedAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Color(0xFFA7A9BE), fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
              error: (err, _) => Center(child: Text('Error loading logs: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
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
  bool _isBlockingActive = false;
  
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

      final storage = ref.read(storageServiceProvider);
      await storage.settingsBox.put('last_accessibility_state', currentAccessibility);

      // Auto-start VPN service if permission is authorized and accessibility service is active, but VPN is not running.
      if (currentAccessibility && isVpnAuthorized && !isVpnRunning) {
        await channel.startBlocking();
        final blocklist = ref.read(blocklistProvider);
        await channel.updateBlocklist(blocklist.domains, blocklist.keywords);
      }

      setState(() {
        _permissionStates = permissionsMap;
        _isBlockingActive = currentAccessibility && (isVpnRunning || (isVpnAuthorized && !_isBlockingActive));
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
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleBlocking(bool targetValue) async {
    final channel = ref.read(platformChannelServiceProvider);
    
    if (targetValue) {
      await _checkCurrentPermissions();
      
      final missingPermissions = <String>[];
      if (!_permissionStates['accessibility']!) missingPermissions.add('accessibility');
      if (!_permissionStates['vpn_authorized']!) missingPermissions.add('vpn');
      if (!_permissionStates['admin']!) missingPermissions.add('admin');
      
      if (missingPermissions.isNotEmpty) {
        _showPermissionBottomSheet(missingPermissions);
        return;
      }

      await channel.startBlocking();
      
      final blocklist = ref.read(blocklistProvider);
      await channel.updateBlocklist(blocklist.domains, blocklist.keywords);
      
      ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'status': true});
      setState(() {
        _isBlockingActive = true;
      });
    } else {
      ref.read(bypassGuardProvider.notifier).startBypassRequest(60);
    }
  }

  void _showPermissionBottomSheet(List<String> missing) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1E29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                     'SYSTEM PERMISSIONS REQUIRED',
                     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Curb Habit needs system level services to scan content and filter network DNS queries.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFA7A9BE)),
                  ),
                  const SizedBox(height: 24),
                  
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('1. Accessibility Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Scans screen layouts for keyword blocks', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12)),
                    trailing: _permissionStates['accessibility']!
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () {
                              _requestSinglePermission('accessibility');
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8906)),
                            child: const Text('GRANT', style: TextStyle(fontSize: 12, color: Colors.black)),
                          ),
                  ),
                  const Divider(color: Color(0xFF2E2F3E)),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('2. Local VPN Connection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Enforces DNS sinkholes on domain blocks', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12)),
                    trailing: _permissionStates['vpn_authorized']!
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () {
                              _requestSinglePermission('vpn');
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8906)),
                            child: const Text('GRANT', style: TextStyle(fontSize: 12, color: Colors.black)),
                          ),
                  ),
                  const Divider(color: Color(0xFF2E2F3E)),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('3. Device Administrator', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Uninstall prevention guard', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12)),
                    trailing: _permissionStates['admin']!
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () {
                              _requestSinglePermission('admin');
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8906)),
                            child: const Text('GRANT', style: TextStyle(fontSize: 12, color: Colors.black)),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bypassState = ref.watch(bypassGuardProvider);
    final blocklistState = ref.watch(blocklistProvider);
    final domains = blocklistState.domains;
    final keywords = blocklistState.keywords;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bypassState.isBypassRequested) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E29),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.shield_outlined, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text(
                    'BYPASS DELAY ACTIVE',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Blocker disabling request starts a 60s cooldown. Take a deep breath.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12),
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
                        },
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFA7A9BE)),
                        child: const Text('Cancel Request'),
                      ),
                      if (bypassState.canConfirmBypass)
                        ElevatedButton(
                          onPressed: () async {
                            final channel = ref.read(platformChannelServiceProvider);
                            await channel.stopBlocking();
                            ref.read(bypassGuardProvider.notifier).completeBypass();
                            ref.read(habitLogsProvider.notifier).addLog('blocker_stopped', {'status': false});
                            setState(() {
                              _isBlockingActive = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          child: const Text('Confirm Turn Off', style: TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E29),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isBlockingActive ? const Color(0xFFFF8906) : const Color(0xFF2E2F3E),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Content Block Engine',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isBlockingActive ? 'ACTIVE & FILTERING' : 'INACTIVE',
                            style: TextStyle(
                              color: _isBlockingActive ? const Color(0xFFFF8906) : const Color(0xFFA7A9BE),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _isBlockingActive,
                        activeColor: const Color(0xFFFF8906),
                        onChanged: (val) => _toggleBlocking(val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF2E2F3E)),
                  const SizedBox(height: 8),
                  const Text(
                    'Android: Accessibility text scanner & Local DNS VPN.\n'
                    'iOS: System Web Filters & Screen Time restrictions.',
                    style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACTIVE WEB DOMAINS FILTERED',
                style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
              ),
              if (blocklistState.isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFF8906)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: domains
                .map((d) => Chip(
                      label: Text(d, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: const Color(0xFF1F1E29),
                      side: const BorderSide(color: Color(0xFF2E2F3E)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACTIVE KEYWORDS BLOCKED',
                style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
              ),
              if (blocklistState.isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFF8906)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keywords
                .map((k) => Chip(
                      label: Text(k, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: const Color(0xFF1F1E29),
                      side: const BorderSide(color: Color(0xFF2E2F3E)),
                    ))
                .toList(),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {
              _checkCurrentPermissions();
              ref.read(blocklistProvider.notifier).fetchAndSync();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Sync Configurations'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E2F3E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// 3. Anonymous Profile Tab
class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final username = authState.profile?.username ?? 'CalmingExplorer2019';
    final isPremium = authState.profile?.isPremium ?? false;
    final isSupporter = authState.profile?.isSupporter ?? false;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1E29),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isPremium ? const Color(0xFFFF8906) : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPremium
                      ? const Color(0xFFFF8906).withOpacity(0.15)
                      : Colors.transparent,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFFFF8906).withOpacity(0.1),
                  child: const Icon(Icons.face_retouching_natural, size: 36, color: Color(0xFFFF8906)),
                ),
                const SizedBox(height: 16),
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2F3E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 12, color: Color(0xFFA7A9BE)),
                      SizedBox(width: 4),
                      Text(
                        '100% Anonymous Profiling',
                        style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(color: Color(0xFF2E2F3E)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Account Tier:',
                      style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 14),
                    ),
                    Text(
                      isPremium ? 'PREMIUM SUBSCRIBER' : 'FREE SUBSCRIPTION',
                      style: TextStyle(
                        color: isPremium ? const Color(0xFFFF8906) : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              ref.read(authProvider.notifier).togglePremium();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isPremium ? 'Downgraded to Free tier. Syncing paused.' : 'Upgraded to Premium! Database syncing started.',
                  ),
                  backgroundColor: const Color(0xFFFF8906),
                  action: SnackBarAction(
                    label: 'Dismiss',
                    textColor: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                  ),
                ),
              );
            },
            icon: Icon(isPremium ? Icons.star_border : Icons.star, size: 20),
            label: Text(
              isPremium ? 'Cancel Premium Plan (Demo)' : 'Upgrade to Premium Plan (Demo)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPremium ? const Color(0xFF1F1E29) : const Color(0xFFFF8906),
              foregroundColor: isPremium ? const Color(0xFFFF8906) : const Color(0xFF0F0E17),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isPremium ? const BorderSide(color: Color(0xFFFF8906)) : BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isPremium) ...[
            ElevatedButton.icon(
              onPressed: () async {
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
                          textColor: Colors.white,
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
                          textColor: Colors.white,
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          },
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.sync, size: 20),
              label: const Text('Force Cloud Sync Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F1E29),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF2E2F3E)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => isSupporter
                      ? const SupporterInboxScreen()
                      : const SupportersListScreen(),
                ),
              );
            },
            icon: Icon(isSupporter ? Icons.inbox : Icons.support_agent, size: 20),
            label: Text(
              isSupporter ? 'My Supporter Inbox' : 'Talk to a Supporter',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F1E29),
              foregroundColor: const Color(0xFFFF8906),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFFF8906)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppBlockerSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings_suggest, size: 20),
            label: const Text(
              'App Guard Settings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F1E29),
              foregroundColor: const Color(0xFFFF8906),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFFF8906)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              ref.read(authProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text(
              'Sign Out of Application',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
          ],
        ),
      );
    }
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'YOUR ACCOUNTABILITY BUDDY',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          if (currentProfile?.buddyId != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E29),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2F3E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFFFF8906)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Linked Accountability Partner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('Your habit logs are visible to this buddy.', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(authProvider.notifier).unlinkBuddy();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    child: const Text('UNLINK'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1E29),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2F3E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add a Buddy to keep you accountable. Search by their anonymous username:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Search Username (e.g. CalmEagle2019)',
                            hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _isSearching
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8906)))
                            : const Icon(Icons.search, color: Color(0xFFFF8906)),
                        onPressed: _performSearch,
                      ),
                    ],
                  ),
                  if (_searchError != null) ...[
                    const SizedBox(height: 8),
                    Text(_searchError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                  if (_searchResult != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF2E2F3E)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_searchResult!.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ElevatedButton(
                          onPressed: () {
                            ref.read(authProvider.notifier).linkBuddy(_searchResult!.id);
                            setState(() {
                              _searchResult = null;
                              _searchController.clear();
                            });
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8906)),
                          child: const Text('LINK BUDDY', style: TextStyle(color: Colors.black, fontSize: 12)),
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
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          linkedPartnersAsync.when(
            data: (partners) {
              if (partners.isEmpty) {
                return const Card(
                  color: Color(0xFF1F1E29),
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No users have linked you as their buddy yet. Ask them to search for your username on their app!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 13),
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
            loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
            error: (err, _) => Center(child: Text('Error loading partners: $err', style: const TextStyle(color: Colors.red))),
          ),
        ],
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
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2F3E)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(widget.partner.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Linked Partner', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 11)),
            trailing: Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: const Color(0xFFFF8906),
            ),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
          ),
          if (_isExpanded) ...[
            const Divider(color: Color(0xFF2E2F3E), height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Consumer(
                builder: (context, ref, child) {
                  final logsAsync = ref.watch(partnerLogsProvider(widget.partner.id));

                  return logsAsync.when(
                    data: (logs) {
                      if (logs.isEmpty) {
                        return const Text('No log entries registered.', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12));
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logs.length > 5 ? 5 : logs.length,
                        itemBuilder: (context, logIndex) {
                          final log = logs[logIndex];
                          final isBlock = log.eventType == 'block_triggered' || log.eventType == 'blocker_stopped';
                          final icon = isBlock ? Icons.warning_amber_rounded : Icons.info_outline;
                          final iconColor = isBlock ? Colors.redAccent : const Color(0xFFFF8906);

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
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '${log.loggedAt.hour}:${log.loggedAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: Color(0xFFA7A9BE), fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8906)))),
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
          color: const Color(0xFF1F1E29),
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
                    'ALERT: ${alert.partnerName.toUpperCase()}',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
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
      data: (data) => SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStreakSection(data),
            const SizedBox(height: 24),
            _buildHeatmapSection(data),
            const SizedBox(height: 24),
            _buildUrgesChartSection(data),
            const SizedBox(height: 24),
            _buildBadgesSection(data),
            const SizedBox(height: 24),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error loading analytics: $err', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

  Widget _buildStreakSection(AnalyticsState data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2F3E)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Icon(Icons.local_fire_department, color: Color(0xFFFF8906), size: 48),
              const SizedBox(height: 8),
              Text(
                '${data.currentStreak} DAYS',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Current Streak',
                style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12),
              ),
            ],
          ),
          Container(width: 1, height: 60, color: const Color(0xFF2E2F3E)),
          Column(
            children: [
              const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 48),
              const SizedBox(height: 8),
              Text(
                '${data.longestStreak} DAYS',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Longest Streak',
                style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
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
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2F3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '35-DAY FOCUS CALENDAR',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
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
              
              Color cellColor = const Color(0xFF0F0E17);
              String tooltip = "No activity recorded";

              if (data.violationDays.contains(dateStr)) {
                cellColor = Colors.redAccent.withOpacity(0.8);
                tooltip = "Urge recorded";
              } else if (data.cleanDays.contains(dateStr)) {
                cellColor = const Color(0xFF2E8B57);
                tooltip = "Clean day focus maintained";
              }

              return Tooltip(
                message: "${date.day}/${date.month} - $tooltip",
                child: Container(
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: cellColor == const Color(0xFF0F0E17)
                          ? const Color(0xFF2E2F3E)
                          : Colors.transparent,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ColorLegendItem(color: Color(0xFF0F0E17), label: 'Inactive'),
              SizedBox(width: 12),
              _ColorLegendItem(color: Color(0xFF2E8B57), label: 'Clean'),
              SizedBox(width: 12),
              _ColorLegendItem(color: Colors.redAccent, label: 'Triggered'),
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
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2F3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'URGES BY TIME OF DAY',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 20),
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
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2F3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FOCUS MILESTONES & BADGES',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
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
              final Color cardColor = badge.isUnlocked ? const Color(0xFF2E2F3E) : const Color(0xFF16151D);
              final Color accentColor = badge.isUnlocked ? const Color(0xFFFF8906) : Colors.white24;

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
                    color: badge.isUnlocked ? const Color(0xFFFF8906).withOpacity(0.3) : const Color(0xFF2E2F3E),
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
                        color: badge.isUnlocked ? Colors.white : Colors.white30,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badge.isUnlocked ? const Color(0xFFA7A9BE) : Colors.white12,
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
            border: Border.all(color: color == const Color(0xFF0F0E17) ? const Color(0xFF2E2F3E) : Colors.transparent),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFFA7A9BE), fontSize: 11)),
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
            color: count > 0 ? const Color(0xFFFF8906) : Colors.white30,
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
            color: const Color(0xFF0F0E17),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2E2F3E)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 32,
            height: barHeight == 0 ? 4 : barHeight,
            decoration: BoxDecoration(
              color: barHeight == 0 ? Colors.white12 : const Color(0xFFFF8906),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFA7A9BE), fontSize: 10),
        ),
      ],
    );
  }
}

