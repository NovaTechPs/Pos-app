import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Puts keyboard focus inside every dialog/sheet as soon as it opens (desktop).
///
/// A field the popup already autofocuses is kept. Otherwise the first text
/// box gets focus (ready to type), else the first item or button in reading
/// order, so arrows and Enter work immediately. Phones are skipped so the
/// on-screen keyboard does not open by itself.
class PopupAutoFocusObserver extends NavigatorObserver {
  PopupAutoFocusObserver({this.enabled});

  /// Defaults to desktop platforms; tests can force it.
  final bool? enabled;

  bool get _active =>
      enabled ??
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_active ||
        (route is! RawDialogRoute && route is! ModalBottomSheetRoute)) {
      return;
    }
    final modal = route as ModalRoute<dynamic>;
    // After the first frame, once the popup's own autofocus has resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() => focusFirst(modal));
    });
  }

  static void focusFirst(ModalRoute<dynamic> route) {
    if (!route.isActive || !route.isCurrent) return;
    final content = route.subtreeContext;
    if (content == null || !content.mounted) return;
    final scope = FocusScope.of(content);
    final context = scope.context;
    if (context == null || !context.mounted) return;
    final current = FocusManager.instance.primaryFocus;
    // Something inside the popup already has focus: keep it.
    if (current != null &&
        current != scope &&
        current.ancestors.contains(scope)) {
      return;
    }
    final text = scope.traversalDescendants.where(
      (node) =>
          node.context
              ?.findAncestorWidgetOfExactType<EditableText>()
              ?.readOnly ==
          false,
    );
    final target = text.isNotEmpty
        ? text.first
        : (FocusTraversalGroup.maybeOf(context)?.findFirstFocus(scope) ??
              scope.traversalDescendants.firstOrNull);
    if (target != null && target != scope) target.requestFocus();
  }
}

/// Arrow-key navigation inside every popup (dialogs, pickers, sheets).
///
/// Sits above the app's routes and only sees keys nobody handled first, so
/// screens and widgets with their own arrow logic (POS cart cells, product
/// lists) keep it. It acts only while focus is inside a popup route, so the
/// main screens (and the barcode field) are unaffected.
///
/// - ↑/↓: item above/below; from a single-line text box, into the list.
/// - ←/→: neighbouring buttons; inside a text box they still move the caret.
/// - Enter is already "activate" for buttons and list items in Flutter.
class PopupArrowNavigation extends StatelessWidget {
  const PopupArrowNavigation({super.key, required this.child});
  final Widget child;

  static KeyEventResult handle(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final vertical =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final horizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (!vertical && !horizontal) return KeyEventResult.ignored;

    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null || !context.mounted) {
      return KeyEventResult.ignored;
    }
    if (ModalRoute.of(context) is! PopupRoute) return KeyEventResult.ignored;

    final text = context.findAncestorWidgetOfExactType<EditableText>();
    if (text != null) {
      // The caret owns ←/→, and ↑/↓ in multi-line fields such as notes.
      if (horizontal || text.maxLines != 1) return KeyEventResult.ignored;
    }

    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      _ => TraversalDirection.right,
    };
    // A freshly opened popup has no focused item yet: start at the first.
    if (focus is FocusScopeNode) {
      return focus.nextFocus()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (focus.focusInDirection(direction)) return KeyEventResult.handled;
    // Lists and mixed layouts: fall back to reading order for ↑/↓.
    if (vertical) {
      final moved = key == LogicalKeyboardKey.arrowDown
          ? focus.nextFocus()
          : focus.previousFocus();
      if (moved) return KeyEventResult.handled;
    }
    // Swallow it inside popups so focus never leaks to the screen behind.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => handle(event),
    child: child,
  );
}
