import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_blocking_modes_provider.dart';
import '../providers/habit_provider.dart';

class AppBlockerSettingsScreen extends ConsumerStatefulWidget {
  const AppBlockerSettingsScreen({super.key});

  @override
  ConsumerState<AppBlockerSettingsScreen> createState() => _AppBlockerSettingsScreenState();
}

class _AppBlockerSettingsScreenState extends ConsumerState<AppBlockerSettingsScreen> {
  final TextEditingController _customPackageController = TextEditingController();

  final Map<String, String> _commonApps = {
    'Google Play Store': 'com.android.vending',
    'Instagram': 'com.instagram.android',
    'Facebook': 'com.facebook.katana',
    'Snapchat': 'com.snapchat.android',
    'TikTok': 'com.zhiliaoapp.musically',
    'YouTube': 'com.google.android.youtube',
    'Reddit': 'com.reddit.frontpage',
    'WhatsApp': 'com.whatsapp',
    'Telegram': 'org.telegram.messenger',
    'Google Chrome': 'com.android.chrome',
    'Brave Browser': 'com.brave.browser',
  };

  @override
  void dispose() {
    _customPackageController.dispose();
    super.dispose();
  }

  void _updateAppMode(String package, String mode, AppBlockingModesState state, AppBlockingModesNotifier notifier) {
    final wasExcluded = state.excludedPackages.contains(package);

    // 1. Clean current lists
    final excluded = List<String>.from(state.excludedPackages)..remove(package);
    final textBox = List<String>.from(state.textBoxOnlyPackages)..remove(package);

    // 2. Add to appropriate list
    if (mode == 'excluded') {
      excluded.add(package);
    } else if (mode == 'textbox') {
      textBox.add(package);
    } // 'full' means it resides in neither, defaulting to full scan

    notifier.updateExcludedPackages(excluded);
    notifier.updateTextBoxOnlyPackages(textBox);

    // Log breach trigger if app protection is disabled
    if (!wasExcluded && mode == 'excluded') {
      ref.read(habitLogsProvider.notifier).addLog(
        'block_triggered',
        {
          'app_package': package,
          'action': 'guard_disabled',
          'message': 'Guard protection was disabled for app: $package',
        },
      );
    }
  }

  void _addCustomPackage(AppBlockingModesState state, AppBlockingModesNotifier notifier) {
    final package = _customPackageController.text.trim();
    if (package.isEmpty) return;

    if (!package.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Android package identifier (e.g. com.example.app)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Default custom package to full scan (not excluded, not text box only)
    _updateAppMode(package, 'full', state, notifier);
    _customPackageController.clear();
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added custom protection: $package'),
        backgroundColor: const Color(0xFFFF8906),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modesState = ref.watch(appBlockingModesProvider);
    final modesNotifier = ref.read(appBlockingModesProvider.notifier);

    // Find all custom packages that are not in our common list
    final commonPackages = _commonApps.values.toSet();
    final customPackages = <String>{
      ...modesState.excludedPackages,
      ...modesState.textBoxOnlyPackages,
    }.difference(commonPackages).where((p) {
      // Don't list system apps that are permanently hardcoded
      return p != 'com.android.settings' &&
             p != 'com.google.android.packageinstaller' &&
             p != 'com.google.android.dialer' &&
             p != 'com.android.contacts';
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        title: const Text(
          'APP GUARD CONFIGURATION',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1F1E29),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1E29),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2F3E)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guarding Modes',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Configure how Curb Habit monitors individual apps on your device to prevent triggers while maintaining usability:\n\n'
                  '• Full Scan: Inspects everything (static texts, layout nodes, lists).\n'
                  '• Input Only: Scans only text boxes and search/chat inputs (prevents false blocks on social feeds).\n'
                  '• Disabled: Excludes this app completely from keyword matching.',
                  style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'COMMON APPS',
            style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),

          ..._commonApps.entries.map((entry) {
            final appName = entry.key;
            final package = entry.value;

            String currentMode = 'full';
            if (modesState.excludedPackages.contains(package)) {
              currentMode = 'excluded';
            } else if (modesState.textBoxOnlyPackages.contains(package)) {
              currentMode = 'textbox';
            }

            return _buildAppModeCard(appName, package, currentMode, modesState, modesNotifier);
          }),

          if (customPackages.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'CUSTOM TARGET APPS',
              style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 12),
            ...customPackages.map((package) {
              String currentMode = 'full';
              if (modesState.excludedPackages.contains(package)) {
                currentMode = 'excluded';
              } else if (modesState.textBoxOnlyPackages.contains(package)) {
                currentMode = 'textbox';
              }

              return _buildAppModeCard(package, package, currentMode, modesState, modesNotifier, isCustom: true);
            }),
          ],

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showAddCustomDialog(modesState, modesNotifier),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Add Custom App Package',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8906),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildAppModeCard(
    String label,
    String package,
    String currentMode,
    AppBlockingModesState state,
    AppBlockingModesNotifier notifier, {
    bool isCustom = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1E29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: currentMode == 'excluded' ? const Color(0xFF2E2F3E) : const Color(0xFFFF8906).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package,
                      style: const TextStyle(color: Color(0xFFA7A9BE), fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (isCustom)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () {
                    // Remove from custom list completely by returning to default full scan
                    final excluded = List<String>.from(state.excludedPackages)..remove(package);
                    final textBox = List<String>.from(state.textBoxOnlyPackages)..remove(package);
                    notifier.updateExcludedPackages(excluded);
                    notifier.updateTextBoxOnlyPackages(textBox);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSegmentButton('Disabled', 'excluded', currentMode, package, state, notifier),
              const SizedBox(width: 8),
              _buildSegmentButton('Input Only', 'textbox', currentMode, package, state, notifier),
              const SizedBox(width: 8),
              _buildSegmentButton('Full Scan', 'full', currentMode, package, state, notifier),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(
    String text,
    String mode,
    String currentMode,
    String package,
    AppBlockingModesState state,
    AppBlockingModesNotifier notifier,
  ) {
    final isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateAppMode(package, mode, state, notifier),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF8906) : const Color(0xFF0F0E17),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF8906) : const Color(0xFF2E2F3E),
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFA7A9BE),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddCustomDialog(AppBlockingModesState state, AppBlockingModesNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1E29),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF2E2F3E)),
          ),
          title: const Text(
            'Add Custom App',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the Android package identifier of the application you wish to manage:',
                style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _customPackageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. com.reddit.frontpage',
                  hintStyle: const TextStyle(color: Color(0xFF5F6072)),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2E2F3E)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFF8906)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFA7A9BE))),
            ),
            TextButton(
              onPressed: () => _addCustomPackage(state, notifier),
              child: const Text('Add App', style: TextStyle(color: Color(0xFFFF8906), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
