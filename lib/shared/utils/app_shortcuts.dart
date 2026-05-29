import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppShortcut {
  final LogicalKeyboardKey key;
  final String label;
  final String? description;
  final VoidCallback action;
  final bool enabled;

  const AppShortcut({
    required this.key,
    required this.label,
    required this.action,
    this.description,
    this.enabled = true,
  });
}

class AppShortcutRegistry {
  static final _instance = AppShortcutRegistry._();
  factory AppShortcutRegistry() => _instance;
  AppShortcutRegistry._();

  final _shortcuts = <LogicalKeyboardKey, AppShortcut>{};
  final _listeners = <VoidCallback>[];

  void register(AppShortcut shortcut) {
    _shortcuts[shortcut.key] = shortcut;
    _notifyListeners();
  }

  void registerAll(List<AppShortcut> shortcuts) {
    for (final s in shortcuts) {
      _shortcuts[s.key] = s;
    }
    _notifyListeners();
  }

  void unregister(LogicalKeyboardKey key) {
    _shortcuts.remove(key);
    _notifyListeners();
  }

  void clear() {
    _shortcuts.clear();
    _notifyListeners();
  }

  bool handleKey(LogicalKeyboardKey key) {
    final shortcut = _shortcuts[key];
    if (shortcut != null && shortcut.enabled) {
      shortcut.action();
      return true;
    }
    return false;
  }

  List<AppShortcut> get all => _shortcuts.values.toList();
  Map<SingleActivator, VoidCallback> get asCallbackShortcuts {
    return {
      for (final entry in _shortcuts.entries)
        if (entry.value.enabled)
          SingleActivator(entry.key): entry.value.action,
    };
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notifyListeners() {
    for (final l in _listeners) {
      l();
    }
  }
}

class ShortcutHelpDialog extends StatelessWidget {
  const ShortcutHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortcuts = AppShortcutRegistry().all.where((s) => s.enabled).toList();

    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SizedBox(
        width: 400,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: shortcuts.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
          itemBuilder: (_, i) {
            final s = shortcuts[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      s.key.keyLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                        if (s.description != null)
                          Text(s.description!, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
