import 'dart:async';

const Object fulusSyncActorUserIdZoneKey = #fulusSyncActorUserId;

String? currentSyncActorUserId() =>
    Zone.current[fulusSyncActorUserIdZoneKey] as String?;
