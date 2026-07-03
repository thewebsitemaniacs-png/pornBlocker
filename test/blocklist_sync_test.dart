import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:habit_breaker/core/services/storage_service.dart';
import 'package:habit_breaker/core/services/platform_channel_service.dart';
import 'package:habit_breaker/features/auth/presentation/providers/auth_provider.dart';
import 'package:habit_breaker/features/habit_engine/presentation/providers/habit_provider.dart';

class TestStorageService implements StorageService {
  @override
  late Box<Map> tasksBox;
  @override
  late Box<Map> logsBox;
  @override
  late Box<dynamic> settingsBox;

  Future<void> initTest() async {
    tasksBox = await Hive.openBox<Map>('test_tasks_bl');
    logsBox = await Hive.openBox<Map>('test_logs_bl');
    settingsBox = await Hive.openBox('test_settings_bl');
  }

  @override
  Future<void> init() async {}
}

class FakeSupabaseClient {
  final Map<String, List<Map<String, dynamic>>> tables = {
    'global_domains': [
      {'value': 'facebook.com'},
    ],
    'global_keywords': [
      {'value': 'distracted'},
    ],
  };

  FakeQueryBuilder from(String table) => FakeQueryBuilder(this, table);
}

class FakeQueryBuilder implements Future<List<Map<String, dynamic>>> {
  final FakeSupabaseClient client;
  final String table;

  FakeQueryBuilder(this.client, this.table);

  Future<dynamic> select() async => client.tables[table]!;

  Future<List<Map<String, dynamic>>> get _future => Future.value(client.tables[table]);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => _future.asStream();

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool Function(Object error)? test}) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) =>
      _future.then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

class FakePlatformChannelService extends PlatformChannelService {
  List<String> domains = [];
  List<String> keywords = [];

  @override
  Future<void> updateBlocklist(List<String> d, List<String> k) async {
    domains = d;
    keywords = k;
  }
}

void main() {
  late Directory tempDir;
  late TestStorageService storageService;
  late FakeSupabaseClient fakeSupabase;
  late FakePlatformChannelService fakeChannel;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);

    storageService = TestStorageService();
    await storageService.initTest();

    fakeSupabase = FakeSupabaseClient();
    fakeChannel = FakePlatformChannelService();

    container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        supabaseClientProvider.overrideWithValue(fakeSupabase),
        platformChannelServiceProvider.overrideWithValue(fakeChannel),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('BlocklistProvider initializes with default values when cache is empty', () {
    final state = container.read(blocklistProvider);
    // YouTube should be in default starter list
    expect(state.domains.contains('youtube.com'), true);
    expect(state.keywords.contains('porn'), true);
  });

  test('BlocklistProvider fetchAndSync loads remote tables and saves to local settings cache', () async {
    final notifier = container.read(blocklistProvider.notifier);
    await notifier.fetchAndSync();

    final state = container.read(blocklistProvider);
    expect(state.domains, ['facebook.com']);
    expect(state.keywords, ['distracted']);

    final cachedDomains = storageService.settingsBox.get('cached_domains');
    expect(cachedDomains, ['facebook.com']);

    final cachedKeywords = storageService.settingsBox.get('cached_keywords');
    expect(cachedKeywords, ['distracted']);

    expect(fakeChannel.domains, ['facebook.com']);
    expect(fakeChannel.keywords, ['distracted']);
  });
}
