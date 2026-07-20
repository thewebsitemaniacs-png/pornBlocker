import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'habit_provider.dart';

class AppBlockingModesState {
  final List<String> excludedPackages;
  final List<String> textBoxOnlyPackages;
  final List<String> customPackages;

  AppBlockingModesState({
    required this.excludedPackages,
    required this.textBoxOnlyPackages,
    required this.customPackages,
  });

  AppBlockingModesState copyWith({
    List<String>? excludedPackages,
    List<String>? textBoxOnlyPackages,
    List<String>? customPackages,
  }) {
    return AppBlockingModesState(
      excludedPackages: excludedPackages ?? this.excludedPackages,
      textBoxOnlyPackages: textBoxOnlyPackages ?? this.textBoxOnlyPackages,
      customPackages: customPackages ?? this.customPackages,
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
    final List<dynamic>? cachedCustom = storage.settingsBox.get('custom_app_packages') as List<dynamic>?;

    final excluded = cachedExcluded != null
        ? List<String>.from(cachedExcluded)
        : List<String>.from(defaultExcluded);

    final textBoxOnly = cachedTextBox != null
        ? List<String>.from(cachedTextBox)
        : List<String>.from(defaultTextBoxOnly);

    final custom = cachedCustom != null
        ? List<String>.from(cachedCustom)
        : <String>[];

    Future.microtask(() => syncToNative());

    return AppBlockingModesState(
      excludedPackages: excluded,
      textBoxOnlyPackages: textBoxOnly,
      customPackages: custom,
    );
  }

  Future<void> addCustomPackage(String package) async {
    final storage = ref.read(storageServiceProvider);
    if (!state.customPackages.contains(package)) {
      final updatedCustom = [...state.customPackages, package];
      await storage.settingsBox.put('custom_app_packages', updatedCustom);
      state = state.copyWith(customPackages: updatedCustom);
    }
  }

  Future<void> removeCustomPackage(String package) async {
    final storage = ref.read(storageServiceProvider);
    final updatedCustom = List<String>.from(state.customPackages)..remove(package);
    final updatedExcluded = List<String>.from(state.excludedPackages)..remove(package);
    final updatedTextBox = List<String>.from(state.textBoxOnlyPackages)..remove(package);

    await storage.settingsBox.put('custom_app_packages', updatedCustom);
    await storage.settingsBox.put('excluded_packages', updatedExcluded);
    await storage.settingsBox.put('text_box_only_packages', updatedTextBox);

    state = state.copyWith(
      customPackages: updatedCustom,
      excludedPackages: updatedExcluded,
      textBoxOnlyPackages: updatedTextBox,
    );
    await syncToNative();
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
