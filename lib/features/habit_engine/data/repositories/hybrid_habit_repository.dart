import '../../../../core/services/storage_service.dart';
import '../../domain/entities/habit_task.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/repositories/habit_repository.dart';

class HybridHabitRepository implements HabitRepository {
  final StorageService _storageService;
  final dynamic _supabaseClient;
  final String? Function() _currentUserIdCallback;

  HybridHabitRepository({
    required StorageService storageService,
    required dynamic supabaseClient,
    required String? Function() currentUserIdCallback,
  })  : _storageService = storageService,
        _supabaseClient = supabaseClient,
        _currentUserIdCallback = currentUserIdCallback;

  String? get _currentUserId => _currentUserIdCallback();

  @override
  Future<List<HabitTask>> getTasks() async {
    final box = _storageService.tasksBox;
    final List<HabitTask> tasks = [];
    for (var key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        tasks.add(HabitTask.fromJson(Map<String, dynamic>.from(value)));
      }
    }
    // Sort tasks: uncompleted first, then by updatedAt descending
    tasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return tasks;
  }

  @override
  Future<void> saveTask(HabitTask task) async {
    final box = _storageService.tasksBox;
    var updatedTask = task;
    
    if (_currentUserId != null) {
      try {
        await _supabaseClient.from('habit_tasks').upsert(task.toJson(excludeSyncFlag: true));
        updatedTask = task.copyWith(synced: true);
      } catch (e) {
        // Offline or connection failure - mark as dirty for future sync
        updatedTask = task.copyWith(synced: false);
      }
    } else {
      updatedTask = task.copyWith(synced: false);
    }
    
    await box.put(updatedTask.id, updatedTask.toJson());
  }

  @override
  Future<void> deleteTask(String id) async {
    final box = _storageService.tasksBox;
    await box.delete(id);

    if (_currentUserId != null) {
      try {
        await _supabaseClient.from('habit_tasks').delete().eq('id', id);
      } catch (e) {
        // Silently catch network failures for local-first operations
      }
    }
  }

  @override
  Future<List<HabitLog>> getLogs() async {
    final box = _storageService.logsBox;
    final List<HabitLog> logs = [];
    for (var key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        logs.add(HabitLog.fromJson(Map<String, dynamic>.from(value)));
      }
    }
    logs.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return logs;
  }

  @override
  Future<void> saveLog(HabitLog log) async {
    final box = _storageService.logsBox;
    var updatedLog = log;

    if (_currentUserId != null) {
      try {
        await _supabaseClient.from('habit_logs').upsert(log.toJson(excludeSyncFlag: true));
        updatedLog = log.copyWith(synced: true);
      } catch (e) {
        updatedLog = log.copyWith(synced: false);
      }
    } else {
      updatedLog = log.copyWith(synced: false);
    }

    await box.put(updatedLog.id, updatedLog.toJson());
  }

  @override
  Future<void> syncWithCloud() async {
    if (_currentUserId == null) return;

    final tasksBox = _storageService.tasksBox;
    final logsBox = _storageService.logsBox;
    final settingsBox = _storageService.settingsBox;

    // 1. Push local unsynced tasks
    final unsyncedTasks = <HabitTask>[];
    for (var key in tasksBox.keys) {
      final value = tasksBox.get(key);
      if (value != null) {
        final task = HabitTask.fromJson(Map<String, dynamic>.from(value));
        if (!task.synced) {
          unsyncedTasks.add(task);
        }
      }
    }

    if (unsyncedTasks.isNotEmpty) {
      try {
        final jsonPayloads = unsyncedTasks.map((t) => t.toJson(excludeSyncFlag: true)).toList();
        await _supabaseClient.from('habit_tasks').upsert(jsonPayloads);
        for (var task in unsyncedTasks) {
          final syncedTask = task.copyWith(synced: true);
          await tasksBox.put(syncedTask.id, syncedTask.toJson());
        }
      } catch (e) {
        // Ignored, will retry on next sync interval
      }
    }

    // 2. Push local unsynced logs
    final unsyncedLogs = <HabitLog>[];
    for (var key in logsBox.keys) {
      final value = logsBox.get(key);
      if (value != null) {
        final log = HabitLog.fromJson(Map<String, dynamic>.from(value));
        if (!log.synced) {
          unsyncedLogs.add(log);
        }
      }
    }

    if (unsyncedLogs.isNotEmpty) {
      try {
        final jsonPayloads = unsyncedLogs.map((l) => l.toJson(excludeSyncFlag: true)).toList();
        await _supabaseClient.from('habit_logs').upsert(jsonPayloads);
        for (var log in unsyncedLogs) {
          final syncedLog = log.copyWith(synced: true);
          await logsBox.put(syncedLog.id, syncedLog.toJson());
        }
      } catch (e) {
        // Ignored, will retry on next sync interval
      }
    }

    // 3. Pull remote updates
    final lastSyncTasksStr = settingsBox.get('last_sync_tasks');
    final lastSyncLogsStr = settingsBox.get('last_sync_logs');
    final nowStr = DateTime.now().toUtc().toIso8601String();

    try {
      var taskQuery = _supabaseClient.from('habit_tasks').select().eq('user_id', _currentUserId);
      if (lastSyncTasksStr != null) {
        taskQuery = taskQuery.gt('updated_at', lastSyncTasksStr);
      }
      final remoteTasksData = await taskQuery;
      
      for (var rawData in remoteTasksData) {
        final remoteTask = HabitTask.fromJson(Map<String, dynamic>.from(rawData)).copyWith(synced: true);
        final localData = tasksBox.get(remoteTask.id);
        if (localData == null) {
          await tasksBox.put(remoteTask.id, remoteTask.toJson());
        } else {
          final localTask = HabitTask.fromJson(Map<String, dynamic>.from(localData));
          if (remoteTask.updatedAt.isAfter(localTask.updatedAt)) {
            await tasksBox.put(remoteTask.id, remoteTask.toJson());
          }
        }
      }
      await settingsBox.put('last_sync_tasks', nowStr);
    } catch (e) {
      // Ignored
    }

    try {
      var logQuery = _supabaseClient.from('habit_logs').select().eq('user_id', _currentUserId);
      if (lastSyncLogsStr != null) {
        logQuery = logQuery.gt('logged_at', lastSyncLogsStr);
      }
      final remoteLogsData = await logQuery;
      for (var rawData in remoteLogsData) {
        final remoteLog = HabitLog.fromJson(Map<String, dynamic>.from(rawData)).copyWith(synced: true);
        await logsBox.put(remoteLog.id, remoteLog.toJson());
      }
      await settingsBox.put('last_sync_logs', nowStr);
    } catch (e) {
      // Ignored
    }
  }

  @override
  Future<void> clearLocalData() async {
    await _storageService.tasksBox.clear();
    await _storageService.logsBox.clear();
    await _storageService.settingsBox.delete('last_sync_tasks');
    await _storageService.settingsBox.delete('last_sync_logs');
  }
}
