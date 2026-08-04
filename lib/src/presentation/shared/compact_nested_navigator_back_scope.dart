import 'package:flutter/widgets.dart';

/// Owns system-back dispatch for a retained compact workspace navigator.
///
/// [hasNestedRoute] must come from the same synchronous state that builds the
/// navigator's page list. This keeps Android's predictive-back eligibility in
/// sync with the business stack without waiting for a [NavigationNotification]
/// from the nested navigator. Inactive retained tabs never participate.
class CompactNestedNavigatorBackScope extends StatefulWidget {
  const CompactNestedNavigatorBackScope({
    super.key,
    required this.active,
    required this.hasNestedRoute,
    required this.navigatorKey,
    required this.onMissingNestedRoute,
    required this.child,
  });

  final bool active;
  final bool hasNestedRoute;
  final GlobalKey<NavigatorState> navigatorKey;
  final VoidCallback onMissingNestedRoute;
  final Widget child;

  bool get handlesSystemBack => active && hasNestedRoute;

  @override
  State<CompactNestedNavigatorBackScope> createState() =>
      _CompactNestedNavigatorBackScopeState();
}

class _CompactNestedNavigatorBackScopeState
    extends State<CompactNestedNavigatorBackScope> {
  bool _handlingPop = false;

  void _handlePop(bool didPop, Object? result) {
    if (didPop || !widget.handlesSystemBack || _handlingPop) {
      return;
    }

    _handlingPop = true;
    final navigator = widget.navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop<Object?>(result);
    } else {
      // The provider can lead the page reconciliation by one frame. Consume
      // the back now and converge the provider instead of leaking it upward.
      widget.onMissingNestedRoute();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handlingPop = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.handlesSystemBack,
      onPopInvokedWithResult: _handlePop,
      child: widget.child,
    );
  }
}
