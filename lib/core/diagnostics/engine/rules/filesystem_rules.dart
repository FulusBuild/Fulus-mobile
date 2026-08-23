import 'dart:io';

import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// File-system rules — backups, receipts, product/customer photos, and
/// any other on-disk read/write this app does (all plain `dart:io`
/// [File] operations; see backup_repository_impl.dart and
/// receipt_repository.dart's own doc comments for the two biggest
/// consumers). Matched on [FileSystemException]'s own `osError`, which
/// carries the operating system's real, stable error text — a `dart:io`
/// core-library type, not a third-party package, so this is not subject
/// to the same version-drift concern noted on the database/network
/// rules above.
class DirectoryUnavailableRule extends DiagnosticRule {
  const DirectoryUnavailableRule();

  @override
  String get name => 'fileSystem.directoryUnavailable';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    if (error is! FileSystemException) return false;
    final osMessage = (error.osError?.message ?? '').toLowerCase();
    return osMessage.contains('no such file or directory') ||
        osMessage.contains('read-only file system') ||
        osMessage.contains('permission denied') ||
        error.message.toLowerCase().contains('cannot open file');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'Fulus could not write to the target storage location — the '
            'folder may be missing, read-only, or the app no longer has '
            'permission to use it.',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) {
    final error = signal.error;
    if (error is! FileSystemException) return const [];
    final path = error.path;
    return path == null ? const [] : [EvidenceItem('Path', path)];
  }
}

class DiskSpaceFileSystemRule extends DiagnosticRule {
  const DiskSpaceFileSystemRule();

  @override
  String get name => 'fileSystem.diskFull';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    if (error is! FileSystemException) return false;
    return (error.osError?.message ?? '').toLowerCase().contains('no space left on device');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'The device has run out of storage space.',
        confidence: DiagnosticConfidence.high,
      );
}

class GenericFileSystemFailureRule extends DiagnosticRule {
  const GenericFileSystemFailureRule();

  @override
  String get name => 'fileSystem.generic';

  @override
  bool matches(DiagnosticSignal signal) => signal.error is FileSystemException;

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'A file read or write failed. See the technical details '
            'below for the exact operating-system error.',
        confidence: DiagnosticConfidence.low,
      );
}

const List<DiagnosticRule> fileSystemRules = [
  DirectoryUnavailableRule(),
  DiskSpaceFileSystemRule(),
  GenericFileSystemFailureRule(),
];
