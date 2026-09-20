import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_shell.dart';
import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/dashboard_summary.dart';
import '../../../../domain/entities/report.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/domain/money_transaction.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider, moneyRepositoryProvider;
import '../../../money/presentation/widgets/transaction_tile.dart';

/// Owner/manager workspace home. Data and permissions remain repository-backed;