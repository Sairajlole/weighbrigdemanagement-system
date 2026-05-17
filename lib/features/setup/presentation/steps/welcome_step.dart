import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupWizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome to Weighbridge', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Let\'s get your system set up. Choose how you\'d like to proceed.',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: _RoleCard(
                  icon: Icons.shield_outlined,
                  title: 'New Admin',
                  subtitle: 'Create a new company and configure the entire system from scratch.',
                  isSelected: state.role == WizardRole.admin,
                  onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin),
                  scheme: scheme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _RoleCard(
                  icon: Icons.badge_outlined,
                  title: 'New Operator',
                  subtitle: 'Join an existing company using a company code from your admin.',
                  isSelected: state.role == WizardRole.operator,
                  onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.operator),
                  scheme: scheme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _RoleCard(
                  icon: Icons.login_rounded,
                  title: 'Sign In',
                  subtitle: 'Already have an account? Sign in and configure this device.',
                  isSelected: state.role == WizardRole.returning,
                  onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning),
                  scheme: scheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    switch (state.role) {
                      WizardRole.admin => 'You\'ll create an account, set up your company, and configure all hardware and software settings.',
                      WizardRole.operator => 'You\'ll create an account with your admin\'s company code, then configure this device.',
                      WizardRole.returning => 'Sign in with your existing credentials. You\'ll then select which site and weighbridge this device connects to.',
                      WizardRole.undecided => 'Select an option above to continue.',
                    },
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? scheme.primary.withValues(alpha: 0.06)
                : _hovered
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : _hovered
                      ? scheme.outlineVariant
                      : scheme.outlineVariant.withValues(alpha: 0.3),
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? scheme.primary.withValues(alpha: 0.12)
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 20, color: widget.isSelected ? scheme.primary : scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isSelected ? scheme.primary : Colors.transparent,
                      border: Border.all(
                        color: widget.isSelected ? scheme.primary : scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: widget.isSelected
                        ? Icon(Icons.check, size: 12, color: scheme.onPrimary)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(height: 6),
              Text(widget.subtitle, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
