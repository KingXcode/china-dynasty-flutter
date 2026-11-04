import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// Shared UI colors. Historical series keep their separate categorical palette.
abstract final class AppColors {
  static const canvas = Color(0xfff4f7f2);
  static const surface = Color(0xfffefffc);
  static const ink = Color(0xff172923);
  static const secondary = Color(0xff53675f);
  static const subtle = Color(0xff5f7268);
  static const accent = Color(0xff286451);
  static const accentSoft = Color(0xffe3f0e7);
  static const line = Color(0xffdbe4dd);
  static const dock = Color(0xff172d25);
  static const mint = Color(0xffdcf4b5);
}

/// An editorial heading with a quiet technical index, shared by the two views.
class AppPageIntro extends StatelessWidget {
  const AppPageIntro({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String index, title, subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  index,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                height: 1.25,
                letterSpacing: -.8,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          if (MediaQuery.textScalerOf(context).scale(13) < 20)
            const ExcludeSemantics(child: AppOrbitMark(size: 46)),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 13,
          height: 1.6,
          color: AppColors.secondary,
        ),
      ),
    ],
  );
}

/// A small, static exploration motif. Decorative only, never a data encoding.
class AppOrbitMark extends StatelessWidget {
  const AppOrbitMark({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _OrbitMarkPainter());
}

class _OrbitMarkPainter extends CustomPainter {
  const _OrbitMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final radius = size.width * .35;
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = AppColors.accentSoft,
    );
    canvas.save();
    canvas.rotate(-math.pi / 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .9,
        height: size.height * .4,
      ),
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();
    canvas.drawCircle(
      Offset.zero,
      radius * .47,
      Paint()..color = AppColors.mint,
    );
    canvas.drawCircle(
      Offset(radius * .8, -radius * .7),
      3,
      Paint()..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitMarkPainter oldDelegate) => false;
}

/// A custom dock presentation over Cupertino's own tab controller and routes.
/// Its opaque reserved area keeps controls and scroll content above the dock.
class AppNavigationDock extends CupertinoTabBar {
  const AppNavigationDock({
    super.key,
    required super.items,
    this.textScaler = TextScaler.noScaling,
    super.currentIndex,
    super.onTap,
    super.height = 84,
    super.backgroundColor = AppColors.canvas,
    super.activeColor = AppColors.ink,
    super.inactiveColor = const Color(0xffc0d1c6),
    super.iconSize = 20,
    super.border = const Border(),
  });

  // CupertinoTabScaffold suppresses tab scaling; explicitly preserve the user
  // setting for this adaptive horizontal-label presentation.
  final TextScaler textScaler;

  @override
  AppNavigationDock copyWith({
    Key? key,
    List<BottomNavigationBarItem>? items,
    Color? backgroundColor,
    Color? activeColor,
    Color? inactiveColor,
    double? iconSize,
    double? height,
    Border? border,
    int? currentIndex,
    ValueChanged<int>? onTap,
  }) => AppNavigationDock(
    key: key ?? this.key,
    items: items ?? this.items,
    textScaler: textScaler,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    activeColor: activeColor ?? this.activeColor,
    inactiveColor: inactiveColor ?? this.inactiveColor,
    iconSize: iconSize ?? this.iconSize,
    height: height ?? this.height,
    border: border ?? this.border,
    currentIndex: currentIndex ?? this.currentIndex,
    onTap: onTap ?? this.onTap,
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final localizations = CupertinoLocalizations.of(context);
    return Container(
      height: height + bottom,
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottom + 12),
      decoration: const BoxDecoration(color: AppColors.canvas),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.dock,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xff355244)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1a172d25),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (var index = 0; index < items.length; index++)
                  Expanded(
                    child: Semantics(
                      selected: currentIndex == index,
                      button: true,
                      label: items[index].label,
                      hint: localizations.tabSemanticsLabel(
                        tabIndex: index + 1,
                        tabCount: items.length,
                      ),
                      excludeSemantics: true,
                      onTap: onTap == null ? null : () => onTap!(index),
                      child: _DockButton(
                        item: items[index],
                        textScaler: textScaler,
                        selected: currentIndex == index,
                        activeColor: activeColor ?? AppColors.ink,
                        inactiveColor: inactiveColor,
                        iconSize: iconSize,
                        onPressed: onTap == null ? null : () => onTap!(index),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    required this.item,
    required this.textScaler,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.iconSize,
    required this.onPressed,
  });
  final BottomNavigationBarItem item;
  final TextScaler textScaler;
  final bool selected;
  final Color activeColor, inactiveColor;
  final double iconSize;
  final VoidCallback? onPressed;
  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? widget.activeColor : widget.inactiveColor;
    final largeText = widget.textScaler.scale(13) > 17;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? AppColors.mint : const Color(0x00172d25),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _focused
              ? (selected ? AppColors.accent : AppColors.mint)
              : const Color(0x00000000),
          width: 2,
        ),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        minimumSize: const Size(44, 44),
        borderRadius: BorderRadius.circular(26),
        onFocusChange: (value) => setState(() => _focused = value),
        onPressed: widget.onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!largeText) ...[
              IconTheme(
                data: IconThemeData(color: color, size: widget.iconSize),
                child: selected ? widget.item.activeIcon : widget.item.icon,
              ),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                widget.item.label ?? '',
                textScaler: widget.textScaler,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
