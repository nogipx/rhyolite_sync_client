import 'package:obsidian_dart/obsidian_dart.dart';
import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rpc_dart/logger.dart';

final _log = RpcLogger('rhyolite.payment');

/// Shows a subscription payment modal.
///
/// Fetches available products from the server, then lets the user pick one
/// and proceed to payment. Returns true if payment was initiated.
Future<bool> showPaymentModal(
  PluginHandle plugin, {
  required RpcAccountClient authClient,
  required void Function(String url) openUrl,
}) async {
  final products = await authClient.listProducts();

  if (products.isEmpty) return false;

  var selectedPlanId = products.first.planId;

  final result = await showModalWith<bool>(
    plugin,
    build: (ctx) {
      ctx.h3('Subscribe to Rhyolite Sync');
      ctx.spaceVertical(px: 12);

      ctx.spaceVertical(px: 8);

      for (final product in products) {
        final price =
            '${(product.amountKopecks / 100).toStringAsFixed(0)} ₽'
            ' / ${product.periodDays} days';
        ctx.buttonRow([
          ButtonSpec('${product.name}  ·  $price', () async {
            selectedPlanId = product.planId;
            await _pay(
              ctx: ctx,
              authClient: authClient,
              planId: selectedPlanId,
              openUrl: openUrl,
            );
          }, variant: ButtonVariant.primary),
        ]);
        ctx.spaceVertical(px: 4);
      }

      ctx.spaceVertical(px: 8);
      ctx.buttonRow([ButtonSpec('Cancel', () => ctx.close(false))]);
      ctx.onEscape(() => ctx.close(false));
    },
  );
  return result ?? false;
}

Future<void> _pay({
  required ModalContext ctx,
  required RpcAccountClient authClient,
  required String planId,
  required void Function(String url) openUrl,
}) async {
  try {
    final url = await authClient.createPayment(planId: planId);
    if (url == null || url.isEmpty) {
      ctx.close(true);
      return;
    }
    openUrl(url);
    ctx.close(true);
  } catch (e) {
    ctx.showError('Failed to create payment: $e');
  }
}

/// Returns the subscription end date if active, null otherwise.
Future<DateTime?> checkSubscription(RpcAccountClient authClient) async {
  try {
    final sub = await authClient.getSubscription();
    if (!sub.isActive || sub.currentPeriodEnd == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      sub.currentPeriodEnd! * 1000,
    ).toLocal();
  } catch (e) {
    _log.error('checkSubscription error', error: e);
    return null;
  }
}
