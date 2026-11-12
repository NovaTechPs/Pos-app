import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sale_data.dart';

class PosCartKeyboard {
  final nodes = <String, FocusNode>{};
  final scroll = ScrollController();
  FocusNode node(int row, int column) =>
      nodes.putIfAbsent('$row:$column', () => FocusNode());
  void focus(int row, int column) {
    node(row, column).requestFocus();
    final context = node(row, column).context;
    if (context != null) Scrollable.ensureVisible(context, alignment: .5);
  }

  KeyEventResult handle(
    KeyEvent event,
    int row,
    int column,
    int count,
    FocusNode barcode,
  ) {
    if (event is KeyUpEvent || count == 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      barcode.requestFocus();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      focus((row - 1 + count) % count, column);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      focus((row + 1) % count, column);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      focus(column == 2 ? (row + 1) % count : row, (column + 1) % 3);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      focus(column == 0 ? (row - 1 + count) % count : row, (column + 2) % 3);
    } else if (key == LogicalKeyboardKey.home) {
      focus(0, column);
    } else if (key == LogicalKeyboardKey.end) {
      focus(count - 1, column);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void dispose() {
    for (final value in nodes.values) {
      value.dispose();
    }
    scroll.dispose();
  }
}

class PosNumberCell extends StatefulWidget {
  const PosNumberCell({
    super.key,
    required this.value,
    required this.node,
    required this.onKey,
    required this.onValue,
    this.quantity = false,
    this.readOnly = false,
  });
  final double value;
  final FocusNode node;
  final KeyEventResult Function(KeyEvent) onKey;
  final ValueChanged<double> onValue;
  final bool quantity, readOnly;
  @override
  State<PosNumberCell> createState() => _PosNumberCellState();
}

class _PosNumberCellState extends State<PosNumberCell> {
  late final TextEditingController controller = TextEditingController(
    text: formatted,
  );
  String get formatted =>
      widget.quantity ? '${widget.value}' : widget.value.toStringAsFixed(2);
  @override
  void initState() {
    super.initState();
    widget.node.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!widget.node.hasFocus) controller.text = formatted;
  }

  @override
  void didUpdateWidget(PosNumberCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_focusChanged);
      widget.node.addListener(_focusChanged);
    }
    if (!widget.node.hasFocus && oldWidget.value != widget.value) {
      controller.text = formatted;
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_focusChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) => widget.onKey(event),
    child: TextField(
      controller: controller,
      focusNode: widget.node,
      readOnly: widget.readOnly,
      selectAllOnFocus: true,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      ),
      onChanged: (text) {
        final value = SaleData.number(text);
        if (value != null &&
            value >= (widget.quantity ? .01 : 0) &&
            value <= 999999999) {
          widget.onValue(value);
        }
      },
      onTapOutside: (_) {
        if (SaleData.number(controller.text) == null) {
          controller.text = formatted;
        }
      },
    ),
  );
}
