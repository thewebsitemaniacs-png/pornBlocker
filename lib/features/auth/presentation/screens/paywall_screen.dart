import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/habit_engine/presentation/providers/habit_provider.dart';
import 'package:habit_breaker/features/auth/presentation/providers/auth_provider.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  final VoidCallback? onUpgradeSuccess;

  const PaywallScreen({super.key, this.onUpgradeSuccess});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _triggerPayment() async {
    _showSnackbar('Processing simulated payment... Upgraded to Premium!', Colors.green);
    await _upgradeUser();
  }

  Future<void> _upgradeUser() async {
    try {
      await ref.read(authProvider.notifier).activatePremium();
      await ref.read(habitLogsProvider.notifier).addLog(
        'premium_unlocked',
        {'method': 'simulated_payment', 'price': 'INR 99.00'},
      );
      if (widget.onUpgradeSuccess != null) {
        widget.onUpgradeSuccess!();
      }
    } catch (e) {
      _showSnackbar('Upgrade activation failed: $e', Colors.redAccent);
    }
  }

  void _showSnackbar(String message, Color bgColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_person_outlined,
                size: 72,
                color: Color(0xFF5AB2FF),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unlock Content blocker',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Take full control of your digital focus with our premium protection features.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF475569),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              
              // Feature list container
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2EAF4)),
                ),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      Icons.shield_outlined,
                      'Unlimited Domain Filtering',
                      'Block unlimited keywords and malicious web domains.',
                    ),
                    const Divider(color: Color(0xFFE2EAF4), height: 24),
                    _buildFeatureItem(
                      Icons.security_outlined,
                      'Uninstall Prevention Guard',
                      'Locks device admin and prevents stopping background blocker services.',
                    ),
                    const Divider(color: Color(0xFFE2EAF4), height: 24),
                    _buildFeatureItem(
                      Icons.sync_lock_outlined,
                      'Accountability Partner Sync',
                      'Instantly share bypass request alerts and logs with your buddy.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Razorpay checkout action button
              ElevatedButton.icon(
                onPressed: _triggerPayment,
                icon: const Icon(Icons.bolt, size: 22, color: Colors.white),
                label: const Text(
                  'Upgrade to Premium for ₹99/mo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5AB2FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(height: 16),
              
              // Local demo bypass link
              TextButton(
                onPressed: () async {
                  _showSnackbar('Bypassing payment: Unlocking premium demo...', Colors.green);
                  await _upgradeUser();
                },
                child: const Text(
                  'Demo Sandbox: Unlock Instantly',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF5AB2FF).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF5AB2FF), size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
