import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/business_settings.dart';
import 'package:fulus_mobile/domain/entities/draft_cart.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/domain/repositories/business_settings_repository.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';
import 'package:fulus_mobile/domain/repositories/draft_cart_repository.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/features/sell/presentation/cubit/cart_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockDraftCartRepository extends Mock implements DraftCartRepository {}
class MockProductRepository extends Mock implements ProductRepository {}
class MockCustomerRepository extends Mock implements CustomerRepository {}
class MockBusinessSettingsRepository extends Mock implements BusinessSettingsRepository {}

void main() {
  late MockDraftCartRepository drafts;
  late MockProductRepository products;
  late MockCustomerRepository customers;
  late MockBusinessSettingsRepository settings;

  final now = DateTime(2026, 1, 1);

  DraftCart draft(String id, String locationId) => DraftCart(
        localId: id,
        locationId: locationId,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    drafts = MockDraftCartRepository();
    products = MockProductRepository();
    customers = MockCustomerRepository();
    settings = MockBusinessSettingsRepository();

    when(() => drafts.getOrCreateDraftCart(locationId: any(named: 'locationId')))
        .thenAnswer((invocation) async {
      final locationId = invocation.namedArguments[#locationId] as String;
      return draft('draft-$locationId', locationId);
    });
    when(() => drafts.watchDraftCart(any())).thenAnswer(
      (invocation) {
        final id = invocation.positionalArguments.single as String;
        final locationId = id.replaceFirst('draft-', '');
        return Stream.value(draft(id, locationId));
      },
    );
    when(() => drafts.watchItems(any())).thenAnswer((_) => Stream.value(const <DraftCartItem>[]));
    when(() => drafts.watchPayments(any())).thenAnswer((_) => Stream.value(const <DraftCartPayment>[]));
    when(() => settings.watchSettings()).thenAnswer((_) => Stream.value(null));
    when(() => products.watchProducts(locationId: any(named: 'locationId')))
        .thenAnswer((_) => Stream.value(const <ProductWithStock>[]));
  });

  test('CartCubits for A and B keep independent durable location context', () async {
    final cartA = CartCubit(
      draftCartRepository: drafts,
      productRepository: products,
      customerRepository: customers,
      businessSettingsRepository: settings,
      locationId: 'loc-a',
    );
    final cartB = CartCubit(
      draftCartRepository: drafts,
      productRepository: products,
      customerRepository: customers,
      businessSettingsRepository: settings,
      locationId: 'loc-b',
    );

    await Future.wait([
      cartA.stream.firstWhere((state) => state is CartLoaded),
      cartB.stream.firstWhere((state) => state is CartLoaded),
    ]);

    final stateA = cartA.state as CartLoaded;
    final stateB = cartB.state as CartLoaded;

    expect(cartA.locationId, 'loc-a');
    expect(cartB.locationId, 'loc-b');
    expect(stateA.draftCart.locationId, 'loc-a');
    expect(stateB.draftCart.locationId, 'loc-b');
    expect(stateA.draftCart.localId, isNot(stateB.draftCart.localId));

    await cartA.close();
    await cartB.close();
  });
}
