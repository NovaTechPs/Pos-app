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
    this.look,
  });
  final double value;
  final FocusNode node;
  final KeyEventResult Function(KeyEvent) onKey;
  final ValueChanged<double> onValue;
  final bool quantity, readOnly;

  /// The web POS look: a boxed field with its own colors, numbers without needless zeros.
  final PosCellLook? look;
  @override
  State<PosNumberCell> createState() => _PosNumberCellState();
}

class _PosNumberCellState extends State<PosNumberCell> {
  late final TextEditingController controller = TextEditingController(
    text: formatted,
  );
  String get formatted => widget.look != null
      ? PosCellLook.compact(widget.value)
      : widget.quantity
      ? '${widget.value}'
      : widget.value.toStringAsFixed(2);
  @override
  void initState() {
    super.initState();
    widget.node.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!widget.node.hasFocus) {
      controller.text = formatted;
    } else if (SaleData.number(controller.text) != widget.value) {
      // Focus can arrive before the rebuild that brings a recalculated value
      // (price typed, then an arrow straight to the total): show the current one.
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection(baseOffset: 0, extentOffset: formatted.length),
      );
    }
  }

  @override
  void didUpdateWidget(PosNumberCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_focusChanged);
      widget.node.addListener(_focusChanged);
    }
    final stale = SaleData.number(controller.text) != widget.value;
    if (oldWidget.value != widget.value &&
        (!widget.node.hasFocus || (stale && !_typing))) {
      controller.value = TextEditingValue(
        text: formatted,
        selection: widget.node.hasFocus
            ? TextSelection(baseOffset: 0, extentOffset: formatted.length)
            : TextSelection.collapsed(offset: formatted.length),
      );
    }
    _typing = false;
  }

  /// True between the cell's own edit and the rebuild it causes, so that rebuild keeps what was typed.
  bool _typing = false;

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
      style:
          widget.look?.style ??
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      decoration:
          widget.look?.decoration ??
          const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          ),
      onChanged: (text) {
        final value = SaleData.number(text);
        if (value != null &&
            value >= (widget.quantity ? .01 : 0) &&
            value <= 999999999) {
          _typing = true;
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

/// How an invoice cell looks on the desktop POS, copied from the web POS.
class PosCellLook {
  const PosCellLook({required this.style, required this.decoration});
  final TextStyle style;
  final InputDecoration decoration;

  /// 75 → '75', 7.5 → '7.5', 1.25 → '1.25', as the web invoice shows them.
  static String compact(double value) {
    final text = value.toStringAsFixed(2);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }
}
