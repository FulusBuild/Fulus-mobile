import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_employee_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/employee.dart';
import 'package:fulus_mobile/domain/repositories/employee_repository.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';
import 'package:fulus_mobile/domain/entities/location.dart';

class _MockEmployeeRepository extends Mock implements EmployeeRepository {}
class _MockLocationRepository extends Mock implements LocationRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const EmployeeDraft(fullName: 'mock employee'));
  });

  late _MockEmployeeRepository employeeRepository;
  late _MockLocationRepository locationRepository;
  late FulusEmployeeCanonicalReconciler reconciler;

  setUp(() {
    employeeRepository = _MockEmployeeRepository();
    locationRepository = _MockLocationRepository();
    when(() => locationRepository.getLocationByServerId(any()))
        .thenAnswer((_) async => Location(
              localId: 'location-local-1',
              serverId: 'location-server-1',
              name: 'Main shop',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ));
    when(() => employeeRepository.reconcileServerState(
          serverId: any(named: 'serverId'),
          clientReference: any(named: 'clientReference'),
          membershipId: any(named: 'membershipId'),
          cloudUserId: any(named: 'cloudUserId'),
          fullName: any(named: 'fullName'),
          role: any(named: 'role'),
          department: any(named: 'department'),
          position: any(named: 'position'),
          salary: any(named: 'salary'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          dateHired: any(named: 'dateHired'),
          locationId: any(named: 'locationId'),
          isActive: any(named: 'isActive'),
          updatedAt: any(named: 'updatedAt'),
          createdAt: any(named: 'createdAt'),
        )).thenAnswer((_) async {});
    when(() => employeeRepository.reconcileDeleted(any())).thenAnswer((_) async {});
    reconciler = FulusEmployeeCanonicalReconciler(
      repository: employeeRepository,
      locationRepository: locationRepository,
    );
  });

  test('maps authoritative cloud location to the local location identity', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'employee',
        'entity_id': 'employee-server-1',
        'operation': 'upsert',
        'row': {
          'id': 'employee-server-1',
          'client_reference': 'employee-local-1',
          'membership_id': 'membership-1',
          'auth_user_id': 'user-1',
          'full_name': 'Amina Yusuf',
          'role': 'cashier',
          'department': 'Sales',
          'position': 'Cashier',
          'salary': '85000.00',
          'phone': '+2348000000000',
          'email': 'amina@example.com',
          'date_hired': '2026-01-02',
          'location_id': 'location-server-1',
          'is_active': true,
          'created_at': '2026-01-01T10:00:00.000Z',
          'updated_at': '2026-09-30T10:00:00.000Z',
        },
      },
    });

    await reconciler.apply(response);

    verify(() => locationRepository.getLocationByServerId('location-server-1')).called(1);
    verify(() => employeeRepository.reconcileServerState(
          serverId: 'employee-server-1',
          clientReference: 'employee-local-1',
          membershipId: 'membership-1',
          cloudUserId: 'user-1',
          fullName: 'Amina Yusuf',
          role: 'cashier',
          department: 'Sales',
          position: 'Cashier',
          salary: moneyFromMajor(85000),
          phone: '+2348000000000',
          email: 'amina@example.com',
          dateHired: DateTime.parse('2026-01-02'),
          locationId: 'location-local-1',
          isActive: true,
          updatedAt: DateTime.parse('2026-09-30T10:00:00.000Z'),
          createdAt: DateTime.parse('2026-01-01T10:00:00.000Z'),
        )).called(1);
  });

  test('routes canonical delete without creating outbound work', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'employee',
        'entity_id': 'employee-server-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => employeeRepository.reconcileDeleted('employee-server-2')).called(1);
    verifyNever(() => employeeRepository.createEmployee(any()));
  });
}
