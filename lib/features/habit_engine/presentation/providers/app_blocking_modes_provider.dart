import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'habit_provider.dart';


class AppBlockingModesState {
  final List<String> excludedPackages;
  final List<String> textBoxOnlyPackages;

  AppBlockingModesState({
    required this.excludedPackages,
    required this.textBoxOnlyPackages,
  });

  AppBlockingModesState copyWith({
    List<String>? excludedPackages,
    List<String>? textBoxOnlyPackages,
  }) {
    return AppBlockingModesState(
      excludedPackages: excludedPackages ?? this.excludedPackages,
      textBoxOnlyPackages: textBoxOnlyPackages ?? this.textBoxOnlyPackages,
    );
  }
}

class AppBlockingModesNotifier extends Notifier<AppBlockingModesState> {
  static const List<String> defaultExcluded = [
    'com.android.settings',
    'com.google.android.packageinstaller',
    'com.google.android.dialer',
    'com.android.contacts',
    'com.android.vending',
  ];

  static const List<String> defaultTextBoxOnly = [
    'com.facebook.katana',
    'com.instagram.android',
    'com.snapchat.android',
    'com.zhiliaoapp.musically',
  ];

  @override
  AppBlockingModesState build() {
    final storage = ref.watch(storageServiceProvider);
    
    final List<dynamic>? cachedExcluded = storage.settingsBox.get('excluded_packages') as List<dynamic>?;
    final List<dynamic>? cachedTextBox = storage.settingsBox.get('text_box_only_packages') as List<dynamic>?;

    final excluded = cachedExcluded != null
        ? List<String>.from(cachedExcluded)
        : List<String>.from(defaultExcluded);

    final textBoxOnly = cachedTextBox != null
        ? List<String>.from(cachedTextBox)
        : List<String>.from(defaultTextBoxOnly);

    Future.microtask(() => syncToNative());

    return AppBlockingModesState(
      excludedPackages: excluded,
      textBoxOnlyPackages: textBoxOnly,
    );
  }

  Future<void> updateExcludedPackages(List<String> packages) async {
    final storage = ref.read(storageServiceProvider);
    await storage.settingsBox.put('excluded_packages', packages);
    state = state.copyWith(excludedPackages: packages);
    await syncToNative();
  }

  Future<void> updateTextBoxOnlyPackages(List<String> packages) async {
    final storage = ref.read(storageServiceProvider);
    await storage.settingsBox.put('text_box_only_packages', packages);
    state = state.copyWith(textBoxOnlyPackages: packages);
    await syncToNative();
  }

  Future<void> syncToNative() async {
    final channel = ref.read(platformChannelServiceProvider);
    await channel.updateAppBlockingModes(
      state.excludedPackages,
      state.textBoxOnlyPackages,
    );
  }
}

final appBlockingModesProvider = NotifierProvider<AppBlockingModesNotifier, AppBlockingModesState>(() {
  return AppBlockingModesNotifier();
});
