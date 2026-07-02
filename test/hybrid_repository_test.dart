import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:habit_breaker/core/services/storage_service.dart';
import 'package:habit_breaker/features/habit_engine/data/repositories/hybrid_habit_repository.dart';
import 'package:habit_breaker/features/habit_engine/domain/entities/habit_task.dart';

// 1. Fake Storage Service to open non-encrypted test boxes easily
class TestStorageService implements StorageService {
  @override
  late Box<Map> tasksBox;
  @override
  late Box<Map> logsBox;
  @override
  late Box<dynamic> settingsBox;

  Future<void> initTest() async {
    tasksBox = await Hive.openBox<Map>('test_tasks');
    logsBox = await Hive.openBox<Map>('test_logs');
    settingsBox = await Hive.openBox('test_settings');
  }

  @override
  Future<void> init() async {}
}

// 2. Fake Supabase Client to capture queries without network requests
class FakeSupabaseClient {
  final Map<String, List<Map<String, dynamic>>> tables = {
    'habit_tasks': [],
    'habit_logs': [],
  };
  bool throwError = false;

  FakeQueryBuilder from(String table) {
    return FakeQueryBuilder(this, table);
  }
}

class FakeQueryBuilder implements Future<dynamic> {
  final FakeSupabaseClient client;
  final String table;

  FakeQueryBuilder(this.client, this.table);

  FakeQueryBuilder eq(String col, dynamic val) => this;
  FakeQueryBuilder gt(String col, dynamic val) => this;

  Future<dynamic> upsert(dynamic values) async {
    if (client.throwError) throw Exception("Network error");
    final list = client.tables[table]!;
    if (values is List) {
      for (var val in values) {
        final map = Map<String, dynamic>.from(val as Map);
        list.removeWhere((item) => item['id'] == map['id']);
        list.add(map);
      }
    } else {
      final map = Map<String, dynamic>.from(values as Map);
      list.removeWhere((item) => item['id'] == map['id']);
      list.add(map);
    }
    return null;
  }

  Future<dynamic> delete() async {
    return this;
  }

  // Delegate for Future implementation when awaited
  Future<dynamic> get _future {
    if (client.throwError) return Future.error(Exception("Network error"));
    return Future.value(client.tables[table]);
  }

  @override
  Stream<dynamic> asStream() => _future.asStream();

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object error)? test}) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) =>
      _future.then(onValue, onError: onError);

  @override
  Future<dynamic> timeout(Duration timeLimit, {FutureOr<dynamic> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

void main() {
  late Directory tempDir;
  late TestStorageService storageService;
  late FakeSupabaseClient fakeSupabase;
  late HybridHabitRepository repository;
  
  bool isPremium = false;
  String? userId = 'test_user_123';

  setUp(() async {
    // Set up temp directory for Hive
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);

    storageService = TestStorageService();
    await storageService.initTest();

    fakeSupabase = FakeSupabaseClient();

    repository = HybridHabitRepository(
      storageService: storageService,
      supabaseClient: fakeSupabase,
      isPremiumCallback: () => isPremium,
      currentUserIdCallback: () => userId,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('HybridHabitRepository Tests', () {
    test('Saving task in Free Tier saves locally with synced = false, does not upload to Supabase', () async {
      isPremium = false;

      final task = HabitTask(
        id: 'task-1',
        userId: userId!,
        title: 'Overcome Youtube Urge',
        isCompleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.saveTask(task);

      // Verify local box has task
      final localTasks = await repository.getTasks();
      expect(localTasks.length, 1);
      expect(localTasks.first.id, 'task-1');
      expect(localTasks.first.synced, false);

      // Verify remote has nothing
      expect(fakeSupabase.tables['habit_tasks']!.isEmpty, true);
    });

    test('Saving task in Premium Tier uploads to Supabase and marks local copy synced = true', () async {
      isPremium = true;

      final task = HabitTask(
        id: 'task-2',
        userId: userId!,
        title: 'Mindful Breathing',
        isCompleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.saveTask(task);

      // Verify local has task and is marked synced
      final localTasks = await repository.getTasks();
      expect(localTasks.length, 1);
      expect(localTasks.first.id, 'task-2');
      expect(localTasks.first.synced, true);

      // Verify remote contains task
      final remoteTasks = fakeSupabase.tables['habit_tasks']!;
      expect(remoteTasks.length, 1);
      expect(remoteTasks.first['id'], 'task-2');
    });

    test('Sync operation pushes local unsynced tasks to Supabase', () async {
      // 1. Create a task in Free tier (synced = false)
      isPremium = false;
      final task = HabitTask(
        id: 'task-3',
        userId: userId!,
        title: 'Urge Replacement Exercise',
        isCompleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repository.saveTask(task);

      // Verify remote is empty
      expect(fakeSupabase.tables['habit_tasks']!.isEmpty, true);

      // 2. Upgrade user to Premium and Sync
      isPremium = true;
      await repository.syncWithCloud();

      // Verify local is now synced = true
      final localTasks = await repository.getTasks();
      expect(localTasks.first.synced, true);

      // Verify remote contains the task
      expect(fakeSupabase.tables['habit_tasks']!.length, 1);
      expect(fakeSupabase.tables['habit_tasks']!.first['id'], 'task-3');
    });
  });
}
