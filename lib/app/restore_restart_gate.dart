import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/theme/design_tokens.dart';
import '../shared/widgets/widgets.dart';

/// A completed local database restore replaces the SQLite file underneath the
/// process. The current DI graph intentionally does not hot-swap every
/// repository/handler reference, so the only safe running-process boundary is
/// to block business use until the process is restarted and every dependency
/// is rebuilt against the restored database.
class RestoreRestartState extends ChangeNotifier {
  bool _restartRequired = false;

  bool get restartRequired => _restartRequired;

  void requireRestart() {
    if (_restartRequired) return;
    _restartRequired = true;
    notifyListeners();
  }
}

final restoreRestartStateProvider =
    ChangeNotifierProvider<RestoreRestartState>((ref) {
  return RestoreRestartState();
});

class RestoreRestartGate extends ConsumerWidget {
  const RestoreRestartGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restartRequired =
        ref.watch(restoreRestartStateProvider).restartRequired;

    if (!restartRequired) return child;

    return Stack(
      children: [
        child,
        const ModalBarrier(
          dismissible: false,
          color: Colors.black54,
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FulusCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.restart_alt_rounded,
                      size: 36,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Restore complete',
                      style: AppTypography.heading.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your restored database is ready. Close and reopen Fulus before continuing so every part of the app uses the restored data.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FulusActionTile(
                      label: 'Close Fulus',
                      subtitle: 'Reopen the app after it closes.',
                      icon: Icons.power_settings_new_rounded,
                      onTap: SystemNavigator.pop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
