import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../blocking/presentation/providers/bypass_guard_provider.dart';
import '../providers/habit_provider.dart';
import '../../domain/entities/habit_task.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isPremium = authState.profile?.isPremium ?? false;

    // Reactively watch lockout state to lock app interaction
    final bypassState = ref.watch(bypassGuardProvider);

    if (bypassState.isLockoutActive && bypassState.lockoutUntil != null) {
      return LockoutOverlay(lockoutUntil: bypassState.lockoutUntil!);
    }

    final List<Widget> screens = [
      const _HabitTab(),
      const _BlockingTab(),
      const _ProfileTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'HABIT ENGINE'
              : _currentIndex == 1
                  ? 'NATIVE BLOCKER'
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
                  const SnackBar(
                    content: Text('Synchronizing habits database with cloud...'),
                    backgroundColor: Color(0xFFFF8906),
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
            icon: Icon(Icons.fingerprint),
            activeIcon: Icon(Icons.fingerprint_rounded),
            label: 'Profile',
          ),
        ],
      ),
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
    'vpn': false,
    'admin': false,
  };

  final List<String> _domains = ['youtube.com', 'instagram.com', 'tiktok.com', 'pornhub.com', 'xvideos.com'];
  final List<String> _keywords = ['shorts', 'reels', 'doomscroll', 'porn', 'adult', 'xxx'];

  @override
  void initState() {
    super.initState();
    // Fetch initial platform permission states on boot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCurrentPermissions();
    });
  }

  Future<void> _checkCurrentPermissions() async {
    try {
      final channel = ref.read(platformChannelServiceProvider);
      final permissionsMap = await channel.checkPermissions();
      if (permissionsMap is Map) {
        setState(() {
          _permissionStates = Map<String, bool>.from(permissionsMap);
          // Auto-enable blocking state representation if services are running
          _isBlockingActive = _permissionStates['accessibility']! && _permissionStates['vpn']!;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestSinglePermission(String type) async {
    try {
      final channel = ref.read(platformChannelServiceProvider);
      await channel.requestPermissions(type); // Triggers native activity
      // Recheck states in background
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        await _checkCurrentPermissions();
        if (_permissionStates[type] == true) {
          timer.cancel();
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleBlocking(bool targetValue) async {
    final channel = ref.read(platformChannelServiceProvider);
    
    if (targetValue) {
      // 1. Verify permissions are granted before starting services
      await _checkCurrentPermissions();
      final missingPermissions = _permissionStates.entries.where((e) => !e.value).map((e) => e.key).toList();
      
      if (missingPermissions.isNotEmpty) {
        _showPermissionBottomSheet(missingPermissions);
        return;
      }

      // 2. Start services on Native channels
      await channel.startBlocking();
      await channel.updateBlocklist(_domains, _keywords);
      
      ref.read(habitLogsProvider.notifier).addLog('blocker_started', {'status': true});
      setState(() {
        _isBlockingActive = true;
      });
    } else {
      // Deactivation Gated via the 60-Second Bypass Delay Timer
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
                  
                  // Accessibility Row
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

                  // VPN Row
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('2. Local VPN Connection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Enforces DNS sinkholes on domain blocks', style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12)),
                    trailing: _permissionStates['vpn']!
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

                  // Device Admin Row
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active state or countdown delay notifier
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
                  Text(
                    'Blocker disabling request starts a 60s cooldown. Take a deep breath.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: const Color(0xFFA7A9BE), fontSize: 12),
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
            // Default active switch card
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

          const Text(
            'ACTIVE WEB DOMAINS FILTERED',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _domains
                .map((d) => Chip(
                      label: Text(d, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: const Color(0xFF1F1E29),
                      side: const BorderSide(color: Color(0xFF2E2F3E)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          
          const Text(
            'ACTIVE KEYWORDS BLOCKED',
            style: TextStyle(color: Color(0xFFA7A9BE), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _keywords
                .map((k) => Chip(
                      label: Text(k, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: const Color(0xFF1F1E29),
                      side: const BorderSide(color: Color(0xFF2E2F3E)),
                    ))
                .toList(),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _checkCurrentPermissions,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh Permission Check'),
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
                      const SnackBar(
                        content: Text('Sync successful!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sync failed. Please check connection.'),
                        backgroundColor: Colors.redAccent,
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
