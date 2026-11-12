import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PosProductKeyboard extends StatefulWidget {
  const PosProductKeyboard({
    super.key,
    required this.count,
    required this.columns,
    required this.stride,
    required this.controller,
    required this.onActivate,
    required this.builder,
    this.leading = 12,
  });
  final int count, columns;
  final double stride;

  /// Scroll padding above the first row, used to keep the selection visible.
  final double leading;
  final ScrollController controller;
  final ValueChanged<int> onActivate;
  final Widget Function(FocusNode node, int selected, bool focused) builder;
  @override
  State<PosProductKeyboard> createState() => PosProductKeyboardState();
}

class PosProductKeyboardState extends State<PosProductKeyboard> {
  final node = FocusNode();
  int selected = 0;
  void selectFirst() {
    setState(() => selected = 0);
    node.requestFocus();
  }

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    onFocusChange: (_) => setState(() {}),
    onKeyEvent: (_, event) {
      if (event is KeyUpEvent || widget.count == 0) {
        return KeyEventResult.ignored;
      }
      selected = selected.clamp(0, widget.count - 1);
      final key = event.logicalKey;
      int next = selected;
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        widget.onActivate(selected);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        next -= widget.columns;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        next += widget.columns;
      } else if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        final step =
            (key == LogicalKeyboardKey.arrowLeft) ==
                (Directionality.of(context) == TextDirection.rtl)
            ? 1
            : -1;
        if ((selected + step) >= 0 &&
            (selected + step) ~/ widget.columns == selected ~/ widget.columns) {
          next += step;
        }
      } else {
        return KeyEventResult.ignored;
      }
      setState(() => selected = next.clamp(0, widget.count - 1));
      if (widget.controller.hasClients) {
        final position = widget.controller.position;
        final top =
            (selected ~/ widget.columns) * widget.stride + widget.leading;
        final target = top < position.pixels
            ? top
            : top + widget.stride > position.pixels + position.viewportDimension
            ? top + widget.stride - position.viewportDimension
            : position.pixels;
        widget.controller.jumpTo(target.clamp(0, position.maxScrollExtent));
      }
      return KeyEventResult.handled;
    },
    child: widget.builder(node, selected, node.hasFocus),
  );
}
