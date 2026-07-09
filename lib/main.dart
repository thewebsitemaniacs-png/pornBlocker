import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'core/services/storage_service.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'features/habit_engine/presentation/providers/habit_provider.dart';
import 'features/habit_engine/presentation/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize encrypted local database boxes
  final storageService = StorageService();
  await storageService.init();

  // Initialize Supabase. Catch connection failures or invalid placeholders to run locally
  bool isSupabaseInitialized = false;
  if (SupabaseConstants.url != 'YOUR_SUPABASE_PROJECT_URL' &&
      SupabaseConstants.anonKey != 'YOUR_SUPABASE_ANON_KEY') {
    try {
      await Supabase.initialize(
        url: SupabaseConstants.url,
        publishableKey: SupabaseConstants.anonKey,
      );
      isSupabaseInitialized = true;
    } catch (e) {
      // Allow running locally even if Supabase configuration fails
    }
  }

  if (!isSupabaseInitialized) {
    try {
      // Boot a local client placeholder so client references don't crash
      await Supabase.initialize(
        url: 'https://placeholder-project.supabase.co',
        publishableKey: 'placeholder-anon-key-abcde12345',
      );
    } catch (_) {}
  }

  runApp(
    ProviderScope(
      overrides: [
        // Inject initialized StorageService
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const HabitBreakerApp(),
    ),
  );
}

class HabitBreakerApp extends ConsumerWidget {
  const HabitBreakerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'flee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFF8906),
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF8906),
          secondary: Color(0xFFFF8906),
          surface: const Color(0xFF1F1E29),
        ),
      ),
      home: authState.user != null ? const DashboardScreen() : const AuthScreen(),
    );
  }
}
