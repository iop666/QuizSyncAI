import 'package:flutter/material.dart';

/// 配色预设 + 自定义（双端设置页共用）。
/// 仅影响应用主题种子色；SPEC 4.3 的标绿规则颜色不随之变化。
class AccentPresets {
  static const List<(String, Color)> presets = [
    ('品牌绿', Color(0xFF16A34A)),
    ('海蓝', Color(0xFF2563EB)),
    ('青碧', Color(0xFF0891B2)),
    ('紫罗兰', Color(0xFF7C3AED)),
    ('暖橙', Color(0xFFEA580C)),
    ('绯红', Color(0xFFDC2626)),
    ('玫粉', Color(0xFFDB2777)),
  ];

  /// 由色相生成种子色（自定义选色用）。
  static Color fromHue(double degrees) {
    final hsv = HSVColor.fromAHSV(1, degrees % 360, 0.72, 0.45);
    return hsv.toColor();
  }
}

/// 配色选择区：预设色块一行 + 「自定义」打开色相滑杆对话框。
/// 选择后回调 ARGB（含 FF alpha）。
class AccentPicker extends StatefulWidget {
  final int current;
  final ValueChanged<int> onChanged;

  const AccentPicker(
      {super.key, required this.current, required this.onChanged});

  @override
  State<AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<AccentPicker> {
  double _hue = 145;
  bool _customizing = false;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(Color(widget.current));
    _hue = hsv.hue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (name, color) in AccentPresets.presets)
              _swatch(color, name, tooltip: name),
            _swatch(
              Color(widget.current),
              '自定义',
              custom: true,
              tooltip: '自定义配色',
            ),
          ],
        ),
        if (_customizing) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('自定义色相'),
              Expanded(
                child: Slider(
                  value: _hue,
                  min: 0,
                  max: 360,
                  label: '${_hue.round()}°',
                  divisions: 360,
                  activeColor: AccentPresets.fromHue(_hue),
                  onChanged: (v) => setState(() => _hue = v),
                ),
              ),
              IconButton(
                tooltip: '应用自定义配色',
                icon: const Icon(Icons.check),
                onPressed: () {
                  final c = AccentPresets.fromHue(_hue);
                  widget.onChanged(c.toARGB32());
                  setState(() => _customizing = false);
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _swatch(Color color, String name,
      {bool custom = false, String? tooltip}) {
    final selected = !custom && color.toARGB32() == widget.current;
    return IconButton(
      tooltip: tooltip ?? name,
      style: IconButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.all(14),
        shape: CircleBorder(
            side: BorderSide(
                color: selected
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black)
                    : Colors.transparent,
                width: selected ? 3 : 0)),
      ),
      onPressed: () {
        if (custom) {
          setState(() => _customizing = !_customizing);
          return;
        }
        widget.onChanged(color.toARGB32());
        setState(() => _customizing = false);
      },
      // 无障碍语义
      icon: custom
          ? const Icon(Icons.colorize, color: Colors.white)
          : const SizedBox.shrink(),
    );
  }
}
