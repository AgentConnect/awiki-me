import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/handle_recovery_epoch_observation.dart';

void main() {
  const reference = ProductDeviceRegistryEpochResetReference(
    accountUserId: 'account-a',
    ownerIdentityId: 'owner-a',
    previousDid: 'did:wba:awiki.info:user:old',
    currentDid: 'did:wba:awiki.info:user:new',
    bindingGeneration: '2',
  );
  const authorization = ProductDeviceRegistryEpochResetAuthorization(
    reference: reference,
    handle: 'handle.awiki.info',
    sourceKind: ProductIdentityTransitionSourceKind.initiator,
    sourceId: 'operation-a',
  );
  final receipt = ProductDeviceRegistryEpochResetReceipt(
    authorization: authorization,
    appliedAt: DateTime.utc(2026, 11, 3),
  );
  ProductDeviceRegistrySnapshot snapshot(
    ProductDeviceRegistryEpoch epoch, {
    String account = 'account-a',
  }) => ProductDeviceRegistrySnapshot(
    binding: ProductAccountBinding(
      ownerIdentityId: 'owner-a',
      accountId: account,
    ),
    epoch: epoch,
    domainVersion: '1',
    refreshedAt: DateTime.utc(2026, 11, 3),
    devices: const [],
  );
  bool observed({
    ProductDeviceRegistryEpochResetReceipt? applied,
    ProductDeviceRegistrySnapshot? registry,
    ProductDeviceRegistryEpoch? epoch,
  }) => handleRecoveryRegistryResetObserved(
    expected: authorization,
    epoch: epoch ?? reference.targetEpoch,
    receipt: applied,
    snapshot: registry,
  );
  test('authorized reset can be observed before registry refresh', () {
    expect(observed(applied: receipt), isTrue);
  });
  test('new-epoch registry refreshed after activation remains valid', () {
    expect(
      observed(applied: receipt, registry: snapshot(reference.targetEpoch)),
      isTrue,
    );
  });
  test('an empty registry without the exact reset receipt is rejected', () {
    expect(observed(), isFalse);
    const other = ProductDeviceRegistryEpochResetAuthorization(
      reference: reference,
      handle: 'handle.awiki.info',
      sourceKind: ProductIdentityTransitionSourceKind.initiator,
      sourceId: 'operation-other',
    );
    expect(
      observed(
        applied: ProductDeviceRegistryEpochResetReceipt(
          authorization: other,
          appliedAt: DateTime.utc(2026, 11, 3),
        ),
      ),
      isFalse,
    );
  });
  test('old or mixed registry epochs are rejected', () {
    const old = ProductDeviceRegistryEpoch(
      currentDid: 'did:wba:awiki.info:user:old',
      bindingGeneration: '1',
    );
    expect(observed(applied: receipt, epoch: old), isFalse);
    expect(observed(applied: receipt, registry: snapshot(old)), isFalse);
    expect(
      observed(
        applied: receipt,
        registry: snapshot(reference.targetEpoch, account: 'account-other'),
      ),
      isFalse,
    );
  });
}
