import 'package:flutter/material.dart';

import '../../../../../core/diagnostics/models/diagnostic_enums.dart';
import '../../../../../core/theme/design_tokens.dart';

/// Color/icon presentation for [DiagnosticSeverity] and
/// [DiagnosticCategory] — split out from the enums themselves
/// (core/diagnostics/models/diagnostic_enums.dart) specifically so that
/// file can stay Flutter-free and importable from the data layer
/// (tables.dart, via Drift's `textEnum<T>()`), matching this codebase's
/// existing domain/data-stay-Flutter-free discipline. Only the
/// Diagnostics screens import this file.
extension DiagnosticSeverityStyle on DiagnosticSeverity {
  /// Never rely on this alone — [DiagnosticSeverity.label] and [icon]
  /// both carry the same meaning too, since severity must never be
  /// color-only (accessibility requirement).
  Color colorOf(BuildContext context) {
    switch (this) {
      case DiagnosticSeverity.critical:
      case DiagnosticSeverity.error:
        return AppColors.errorOf(context);
      case DiagnosticSeverity.warning:
        return AppColors.warningOf(context);
      case DiagnosticSeverity.info:
        return AppColors.infoOf(context);
    }
  }

  IconData get icon {
    switch (this) {
      case DiagnosticSeverity.critical:
        return Icons.report_gmailerrorred;
      case DiagnosticSeverity.error:
        return Icons.error_outline;
      case DiagnosticSeverity.warning:
        return Icons.warning_amber_rounded;
      case DiagnosticSeverity.info:
        return Icons.info_outline;
    }
  }
}

extension DiagnosticCategoryStyle on DiagnosticCategory {
  IconData get icon {
    switch (this) {
      case DiagnosticCategory.flutterFramework:
        return Icons.widgets_outlined;
      case DiagnosticCategory.dartRuntime:
        return Icons.code;
      case DiagnosticCategory.database:
        return Icons.storage_outlined;
      case DiagnosticCategory.network:
        return Icons.wifi_outlined;
      case DiagnosticCategory.authentication:
        return Icons.lock_outline;
      case DiagnosticCategory.synchronization:
        return Icons.sync_outlined;
      case DiagnosticCategory.fileSystem:
        return Icons.folder_outlined;
      case DiagnosticCategory.exportReporting:
        return Icons.picture_as_pdf_outlined;
      case DiagnosticCategory.platformChannel:
        return Icons.print_outlined;
      case DiagnosticCategory.navigation:
        return Icons.map_outlined;
      case DiagnosticCategory.validation:
        return Icons.rule_outlined;
      case DiagnosticCategory.stateConsistency:
        return Icons.hub_outlined;
      case DiagnosticCategory.configuration:
        return Icons.settings_outlined;
      case DiagnosticCategory.sales:
        return Icons.point_of_sale_outlined;
      case DiagnosticCategory.inventory:
        return Icons.inventory_2_outlined;
      case DiagnosticCategory.startup:
        return Icons.power_settings_new;
      case DiagnosticCategory.unknown:
        return Icons.help_outline;
    }
  }
}
