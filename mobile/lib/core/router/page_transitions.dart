import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/motion.dart';

/// Page builders for `GoRoute.pageBuilder`. All respect reduced-motion settings.
abstract final class AppPages {
  /// Soft cross-fade: splash, onboarding, auth.
  static CustomTransitionPage<void> fade(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.normal,
      transitionsBuilder: (context, animation, secondary, child) {
        if (Motion.reduced(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  /// Horizontal slide plus fade for drill-down navigation (list to detail).
  static CustomTransitionPage<void> slide(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.normal,
      reverseTransitionDuration: Motion.normal,
      transitionsBuilder: (context, animation, secondary, child) {
        if (Motion.reduced(context)) return child;
        final curved =
            CurvedAnimation(parent: animation, curve: Motion.standard);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                    .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Rise from the bottom for creation and edit forms.
  static CustomTransitionPage<void> rise(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      fullscreenDialog: true,
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.normal,
      transitionsBuilder: (context, animation, secondary, child) {
        if (Motion.reduced(context)) return child;
        final curved =
            CurvedAnimation(parent: animation, curve: Motion.emphasized);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                    .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Tab-level destinations inside the app shell: fade only, so the shell does not appear to move.
  static CustomTransitionPage<void> shellTab(
      GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Motion.fast,
      reverseTransitionDuration: Motion.fast,
      transitionsBuilder: (context, animation, secondary, child) {
        if (Motion.reduced(context)) return child;
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}
