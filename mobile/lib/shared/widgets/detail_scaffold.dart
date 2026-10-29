import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.maxWidth = 1000,
    this.fallbackRoute = Routes.leads,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double maxWidth;

  /// Where the back arrow goes when there is nothing to pop (for example after a deep link).
  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go(fallbackRoute),
              ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth), child: body),
      ),
    );
  }
}
