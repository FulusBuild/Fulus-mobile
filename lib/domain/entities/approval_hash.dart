import 'package:json_annotation/json_annotation.dart';

part 'approval_hash.g.dart';

/// One synced-down verifier, scoped to the specific owner it belongs
/// to — Architecture Section 6: the sync-down dataset is "which owners
/// exist and can approve," not a single PIN, since a business can have
/// more than one admin. Deliberately lives here, in domain/entities/,
/// rather than alongside PinHasher in core/security/ — that file
/// depends on the cryptography package (needed for the actual
/// hashing), and this type needs to stay importable from domain-layer
/// files that must have zero Flutter/Drift/third-party-crypto
/// dependencies (this file's own DTOs below, in particular).
class ApprovalPinVerifier {
  const ApprovalPinVerifier({
    required this.userId,
    required this.hash,
    required this.salt,
  });

  final String userId;
  final String hash;
  final String salt;

  /// Plain manual toJson/fromJson rather than json_serializable/
  /// build_runner codegen — three String fields is simple enough not
  /// to need generated code for this, and this type's OWN serialized
  /// form (for SecureStorage) is deliberately independent of the wire
  /// DTOs below, which use their own generated (de)serialization
  /// against a different (snake_case) shape.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'hash': hash,
        'salt': salt,
      };

  factory ApprovalPinVerifier.fromJson(Map<String, dynamic> json) =>
      ApprovalPinVerifier(
        userId: json['userId'] as String,
        hash: json['hash'] as String,
        salt: json['salt'] as String,
      );
}

/// POST /api/auth/approval-pin's body — request-only, mirrors
/// SetApprovalPinRequest exactly (backend/app/schemas/auth.py, verified
/// directly against the endpoint I added in this same session).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class SetApprovalPinRequestDto {
  const SetApprovalPinRequestDto({
    required this.pinHash,
    required this.pinSalt,
  });

  final String pinHash;
  final String pinSalt;

  Map<String, dynamic> toJson() => _$SetApprovalPinRequestDtoToJson(this);
}

/// One entry in GET /api/auth/approval-hashes's response — mirrors
/// ApprovalHashEntry exactly.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ApprovalHashEntryDto {
  const ApprovalHashEntryDto({
    required this.userId,
    required this.pinHash,
    required this.pinSalt,
  });

  final String userId;
  final String pinHash;
  final String pinSalt;

  factory ApprovalHashEntryDto.fromJson(Map<String, dynamic> json) =>
      _$ApprovalHashEntryDtoFromJson(json);

  ApprovalPinVerifier toDomain() =>
      ApprovalPinVerifier(userId: userId, hash: pinHash, salt: pinSalt);
}

/// GET /api/auth/approval-hashes's full response — mirrors
/// ApprovalHashesResponse exactly.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ApprovalHashesResponseDto {
  const ApprovalHashesResponseDto({required this.hashes});

  final List<ApprovalHashEntryDto> hashes;

  factory ApprovalHashesResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ApprovalHashesResponseDtoFromJson(json);
}
