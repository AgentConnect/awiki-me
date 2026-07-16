import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/e2e_semantics.dart';
import '../awiki_me_design.dart';
import '../responsive_layout.dart';

@immutable
class AppPressableState {
  const AppPressableState({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.selected,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool selected;

  bool get interactive => enabled && (hovered || pressed || focused);
}

typedef AppPressableBuilder =
    Widget Function(
      BuildContext context,
      AppPressableState state,
      Widget child,
    );

class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.builder,
    this.selected = false,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    this.borderRadius,
    this.hoverColor,
    this.pressedColor,
    this.focusColor,
    this.scaleOnPress = false,
    this.pressedScale = 0.98,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOutCubic,
    this.tooltip,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.button = true,
    this.focusNode,
    this.autofocus = false,
    this.mouseCursor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final AppPressableBuilder? builder;
  final bool selected;
  final bool enabled;
  final HitTestBehavior behavior;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? pressedColor;
  final Color? focusColor;
  final bool scaleOnPress;
  final double pressedScale;
  final Duration duration;
  final Curve curve;
  final String? tooltip;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final bool button;
  final FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor? mouseCursor;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) {
      return;
    }
    setState(() => _pressed = value);
  }

  void _activate() {
    if (!_enabled) {
      return;
    }
    widget.onTap?.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final enabled = _enabled;
    final state = AppPressableState(
      enabled: enabled,
      hovered: enabled && _hovered,
      pressed: enabled && _pressed,
      focused: enabled && _focused,
      selected: widget.selected,
    );
    final child = widget.builder == null
        ? _AppPressableDefaultVisual(
            state: state,
            borderRadius: widget.borderRadius,
            hoverColor:
                widget.hoverColor ??
                theme.primary.withValues(alpha: state.selected ? 0.08 : 0.06),
            pressedColor:
                widget.pressedColor ??
                theme.primary.withValues(alpha: state.selected ? 0.14 : 0.10),
            focusColor:
                widget.focusColor ?? theme.primary.withValues(alpha: 0.35),
            duration: widget.duration,
            curve: widget.curve,
            child: widget.child,
          )
        : widget.builder!(context, state, widget.child);

    Widget current = AnimatedScale(
      scale: widget.scaleOnPress && state.pressed ? widget.pressedScale : 1,
      duration: widget.duration,
      curve: widget.curve,
      child: child,
    );

    current = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: enabled,
      onFocusChange: (value) {
        if (_focused != value) {
          setState(() => _focused = value);
        }
      },
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor:
            widget.mouseCursor ??
            (enabled ? SystemMouseCursors.click : SystemMouseCursors.basic),
        onEnter: (_) {
          if (enabled && !_hovered) {
            setState(() => _hovered = true);
          }
        },
        onExit: (_) {
          if (_hovered || _pressed) {
            setState(() {
              _hovered = false;
              _pressed = false;
            });
          }
        },
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: enabled ? widget.onTap : null,
          onLongPress: enabled ? widget.onLongPress : null,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: current,
        ),
      ),
    );

    current = e2eSemantics(
      identifier: enabled ? widget.semanticsIdentifier : null,
      label: widget.semanticLabel,
      button: widget.button,
      enabled: enabled,
      child: current,
    );

    if (widget.tooltip != null && widget.tooltip!.trim().isNotEmpty) {
      current = Tooltip(message: widget.tooltip!, child: current);
    }
    return current;
  }
}

class _AppPressableDefaultVisual extends StatelessWidget {
  const _AppPressableDefaultVisual({
    required this.state,
    required this.child,
    required this.hoverColor,
    required this.pressedColor,
    required this.focusColor,
    required this.duration,
    required this.curve,
    this.borderRadius,
  });

  final AppPressableState state;
  final Widget child;
  final Color hoverColor;
  final Color pressedColor;
  final Color focusColor;
  final Duration duration;
  final Curve curve;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final overlayColor = state.pressed
        ? pressedColor
        : state.hovered
        ? hoverColor
        : CupertinoColors.transparent;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: duration,
                curve: curve,
                decoration: BoxDecoration(
                  color: overlayColor,
                  borderRadius: borderRadius,
                  border: state.focused
                      ? Border.all(color: focusColor, width: 1.2)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TopBarActionButton extends StatelessWidget {
  const TopBarActionButton({
    super.key,
    required this.child,
    this.onTap,
    this.semanticsIdentifier,
    this.semanticsLabel,
    this.tooltip,
    this.borderRadius,
    this.scaleOnPress = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsIdentifier;
  final String? semanticsLabel;
  final String? tooltip;
  final BorderRadius? borderRadius;
  final bool scaleOnPress;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: tooltip ?? semanticsLabel,
      button: true,
      enabled: onTap != null,
      scaleOnPress: scaleOnPress,
      pressedScale: 0.94,
      borderRadius:
          borderRadius ?? BorderRadius.circular(responsive.radius(10)),
      child: child,
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.tooltip,
    this.size,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.activeBackgroundColor,
    this.borderColor,
    this.activeBorderColor,
    this.borderRadius,
    this.isActive = false,
    this.isLoading = false,
    this.scaleOnPress = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final String? tooltip;
  final double? size;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? activeBackgroundColor;
  final Color? borderColor;
  final Color? activeBorderColor;
  final BorderRadius? borderRadius;
  final bool isActive;
  final bool isLoading;
  final bool scaleOnPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final resolvedSize = size ?? responsive.compactControlHeight;
    final resolvedRadius =
        borderRadius ?? BorderRadius.circular(responsive.radius(10));
    final enabled = onPressed != null && !isLoading;
    return AppPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: tooltip ?? semanticLabel,
      enabled: enabled,
      selected: isActive,
      borderRadius: resolvedRadius,
      scaleOnPress: scaleOnPress,
      pressedScale: 0.94,
      builder: (context, state, child) {
        final baseBackground = isActive
            ? activeBackgroundColor ?? theme.primary.withValues(alpha: 0.10)
            : backgroundColor ?? CupertinoColors.transparent;
        final overlay = state.pressed
            ? theme.primary.withValues(alpha: isActive ? 0.16 : 0.10)
            : state.hovered
            ? theme.primary.withValues(alpha: isActive ? 0.12 : 0.06)
            : CupertinoColors.transparent;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: resolvedSize,
          height: resolvedSize,
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.alphaBlend(overlay, baseBackground),
            borderRadius: resolvedRadius,
            border: Border.all(
              color: state.focused
                  ? theme.primary.withValues(alpha: 0.45)
                  : isActive
                  ? activeBorderColor ??
                        borderColor ??
                        CupertinoColors.transparent
                  : borderColor ?? CupertinoColors.transparent,
              width: state.focused ? 1.2 : 1,
            ),
          ),
          child: isLoading
              ? CupertinoActivityIndicator(radius: responsive.displayScaled(8))
              : child,
        );
      },
      child: child,
    );
  }
}

class AppPressableTile extends StatelessWidget {
  const AppPressableTile({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.selected = false,
    this.borderRadius,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.border,
    this.padding,
    this.duration = const Duration(milliseconds: 140),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final bool selected;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Border? border;
  final EdgeInsets? padding;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final radius = borderRadius ?? BorderRadius.circular(responsive.radius(12));
    return AppPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      enabled: onTap != null,
      selected: selected,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      borderRadius: radius,
      builder: (context, state, child) {
        final baseColor = selected
            ? selectedBackgroundColor ?? theme.primary.withValues(alpha: 0.08)
            : backgroundColor ?? CupertinoColors.transparent;
        final overlay = state.pressed
            ? theme.primary.withValues(alpha: selected ? 0.12 : 0.08)
            : state.hovered
            ? theme.primary.withValues(alpha: selected ? 0.08 : 0.04)
            : CupertinoColors.transparent;
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: padding,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: radius,
            border: state.focused
                ? Border.all(color: theme.primary.withValues(alpha: 0.38))
                : border,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: overlay,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }
}

class AppPressableText extends StatelessWidget {
  const AppPressableText({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.tooltip,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final String? tooltip;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: tooltip ?? semanticLabel,
      enabled: onTap != null,
      borderRadius: borderRadius ?? BorderRadius.circular(responsive.radius(8)),
      builder: (context, state, child) {
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          style: DefaultTextStyle.of(context).style.copyWith(
            color: state.pressed
                ? theme.primaryDark
                : state.hovered || state.focused
                ? theme.primary
                : null,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

class AppPressableScale extends StatelessWidget {
  const AppPressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.tooltip,
    this.borderRadius,
    this.pressedScale = 0.98,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final String? tooltip;
  final BorderRadius? borderRadius;
  final double pressedScale;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: tooltip ?? semanticLabel,
      enabled: onTap != null,
      borderRadius: borderRadius,
      scaleOnPress: true,
      pressedScale: pressedScale,
      child: child,
    );
  }
}

class AppPressableOpacity extends StatelessWidget {
  const AppPressableOpacity({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticsIdentifier,
    this.tooltip,
    this.borderRadius,
    this.disabledOpacity = 0.5,
    this.pressedOpacity = 0.72,
    this.hoveredOpacity = 0.88,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticsIdentifier;
  final String? tooltip;
  final BorderRadius? borderRadius;
  final double disabledOpacity;
  final double pressedOpacity;
  final double hoveredOpacity;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: tooltip ?? semanticLabel,
      enabled: onTap != null,
      borderRadius: borderRadius,
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? disabledOpacity
            : state.pressed
            ? pressedOpacity
            : state.hovered || state.focused
            ? hoveredOpacity
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: child,
    );
  }
}

class AwikiAssetIcon extends StatelessWidget {
  const AwikiAssetIcon({
    super.key,
    required this.assetName,
    this.size = 24,
    this.color,
  });

  final String assetName;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

class AppCardSection extends StatelessWidget {
  const AppCardSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AwikiMeColors.surface,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AwikiMeDecorations.card(context: context, color: color),
      padding: padding,
      child: child,
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AwikiMeInsets.lg),
    this.color,
    this.radius = AwikiMeRadii.md,
    this.margin,
    this.constraints,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final EdgeInsets? margin;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.awikiTheme.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.backgroundColor = const Color(0xFFFFF4D6),
    this.foregroundColor = AwikiMeColors.primaryDark,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      child: Text(
        label,
        style: AwikiMeTextStyles.pillLabel.copyWith(
          fontSize: responsive.metaSm,
          color: foregroundColor == AwikiMeColors.primaryDark
              ? theme.primaryDark
              : foregroundColor,
        ),
      ),
    );
  }
}

class AppSectionDivider extends StatelessWidget {
  const AppSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: context.awikiTheme.border),
        ),
      ),
    );
  }
}

class AppDropMenuItem {
  const AppDropMenuItem({
    required this.label,
    this.onTap,
    this.icon,
    this.destructive = false,
    this.highlighted = false,
    this.semanticsIdentifier,
  });

  final String label;
  final FutureOr<void> Function()? onTap;
  final IconData? icon;
  final bool destructive;
  final bool highlighted;
  final String? semanticsIdentifier;
}

class AppDropMenu extends StatelessWidget {
  const AppDropMenu({super.key, this.title, required this.items});

  final String? title;
  final List<AppDropMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: responsive.scaledInsets(const EdgeInsets.all(16)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(responsive.radius(24)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null && title!.trim().isNotEmpty) ...<Widget>[
                  Padding(
                    padding: responsive.scaledInsets(
                      const EdgeInsets.fromLTRB(24, 18, 24, 14),
                    ),
                    child: Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.metaSm,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                  Container(height: 1, color: theme.border),
                ],
                for (var index = 0; index < items.length; index++) ...<Widget>[
                  _AppDropMenuButton(item: items[index]),
                  if (index != items.length - 1)
                    Container(height: 1, color: theme.border),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDropMenuButton extends StatelessWidget {
  const _AppDropMenuButton({required this.item});

  final AppDropMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    Color foregroundColor = theme.title;
    if (item.destructive) {
      foregroundColor = theme.alert;
    } else if (item.highlighted) {
      foregroundColor = theme.primary;
    }

    return AppPressable(
      onTap: item.onTap == null
          ? null
          : () async {
              Navigator.of(context).pop();
              await item.onTap?.call();
            },
      semanticLabel: item.label,
      semanticsIdentifier: item.semanticsIdentifier,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: responsive.isPhone ? 68 : responsive.scaled(56),
        child: Center(
          child: item.icon == null
              ? Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: responsive.titleLg,
                    fontWeight: item.highlighted || item.destructive
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: foregroundColor,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: responsive.iconMd,
                      color: foregroundColor,
                    ),
                    SizedBox(width: responsive.spacing(12)),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.titleLg,
                        fontWeight: item.highlighted || item.destructive
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: foregroundColor,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.placeholder,
    this.enabled = true,
    this.multiline = false,
    this.keyboardType,
    this.showLabel = true,
    this.prefix,
    this.suffix,
    this.backgroundColor,
    this.semanticsIdentifier,
    this.semanticsLabel,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final bool enabled;
  final bool multiline;
  final TextInputType? keyboardType;
  final bool showLabel;
  final Widget? prefix;
  final Widget? suffix;
  final Color? backgroundColor;
  final String? semanticsIdentifier;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final rawTextField = CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      decoration: null,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 5 : 1,
      textAlign: TextAlign.left,
      keyboardType: keyboardType,
      padding: multiline
          ? EdgeInsets.symmetric(vertical: responsive.spacing(10))
          : EdgeInsets.zero,
      enabled: enabled,
      style: AwikiMeTextStyles.inputText.copyWith(
        fontSize: responsive.bodyMd,
        color: theme.title,
      ),
      placeholderStyle: AwikiMeTextStyles.inputText.copyWith(
        fontSize: responsive.bodyMd,
        color: theme.secondaryText,
      ),
    );
    final identifier = e2eIdentifier(semanticsIdentifier);
    final textField = identifier == null
        ? rawTextField
        : Semantics(
            identifier: identifier,
            label: semanticsLabel ?? label,
            textField: true,
            child: rawTextField,
          );
    return AppSurface(
      color: backgroundColor ?? theme.subtleSurface,
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showLabel) ...<Widget>[
            Text(
              label,
              style: AwikiMeTextStyles.fieldLabel.copyWith(
                fontSize: responsive.metaSm,
                color: theme.secondaryText,
              ),
            ),
            SizedBox(height: responsive.spacing(6)),
          ],
          if (multiline)
            textField
          else
            SizedBox(
              height: responsive.compactControlHeight,
              child: Row(
                children: <Widget>[
                  if (prefix != null) ...<Widget>[
                    prefix!,
                    SizedBox(width: responsive.spacing(10)),
                  ],
                  Expanded(child: Center(child: textField)),
                  if (suffix != null) ...<Widget>[
                    SizedBox(width: responsive.spacing(8)),
                    suffix!,
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.semanticsIdentifier,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: responsive.isPhone ? 0.97 : 0.985,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? 0.5
            : state.pressed
            ? 0.88
            : state.hovered || state.focused
            ? 0.96
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.controlHeight),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(16),
          vertical: responsive.spacing(10),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[
              AwikiMePalette.actionBlue,
              AwikiMePalette.actionBlueDeep,
            ],
          ),
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x240B65F8),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: responsive.bodyMd,
              height: 1,
              forceStrutHeight: true,
            ),
            style: AwikiMeTextStyles.buttonLabel.copyWith(
              color: theme.primaryForeground,
              fontSize: responsive.bodyMd,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.semanticsIdentifier,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: responsive.isPhone ? 0.97 : 0.985,
      selected: false,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      builder: (context, state, child) {
        final overlay = state.pressed
            ? theme.primary.withValues(alpha: 0.10)
            : state.hovered || state.focused
            ? theme.primary.withValues(alpha: 0.05)
            : CupertinoColors.transparent;
        return AnimatedOpacity(
          opacity: state.enabled ? 1 : 0.5,
          duration: const Duration(milliseconds: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: overlay,
              borderRadius: BorderRadius.circular(responsive.radius(9)),
            ),
            child: child,
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.controlHeight),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(16),
          vertical: responsive.spacing(10),
        ),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(color: AwikiMePalette.actionBlueBorder),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: responsive.bodyMd,
              height: 1,
              forceStrutHeight: true,
            ),
            style: AwikiMeTextStyles.buttonLabel.copyWith(
              color: AwikiMePalette.actionInk,
              fontSize: responsive.bodyMd,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: responsive.isPhone ? 0.97 : 0.985,
      borderRadius: BorderRadius.circular(AwikiMeRadii.sm),
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? 0.5
            : state.pressed
            ? 0.82
            : state.hovered || state.focused
            ? 0.92
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: AppSurface(
        padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
        color: theme.dangerContainer,
        radius: AwikiMeRadii.sm,
        constraints: BoxConstraints(minHeight: responsive.controlHeight),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: responsive.bodyMd,
              height: 1,
              forceStrutHeight: true,
            ),
            style: AwikiMeTextStyles.buttonLabel.copyWith(
              color: theme.danger,
              fontSize: responsive.bodyMd,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class AppInlineLinkRow extends StatelessWidget {
  const AppInlineLinkRow({
    super.key,
    required this.label,
    this.icon = CupertinoIcons.link,
    this.iconAsset,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String? iconAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(12),
      backgroundColor: theme.subtleSurface,
      child: Padding(
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        child: Row(
          children: <Widget>[
            if (iconAsset != null)
              AwikiAssetIcon(
                assetName: iconAsset!,
                color: theme.primaryDark,
                size: responsive.iconSm,
              )
            else
              Icon(icon, color: theme.primaryDark, size: responsive.iconSm),
            SizedBox(width: responsive.spacing(8)),
            Expanded(
              child: Text(
                label,
                style: AwikiMeTextStyles.listSubtitle.copyWith(
                  fontSize: responsive.bodySm,
                  color: theme.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppActionRow extends StatelessWidget {
  const AppActionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      onTap: onTap,
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCardSection(
      color: context.awikiTheme.subtleSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AwikiMeTextStyles.sectionTitle.copyWith(
              color: context.awikiTheme.secondaryText,
              fontSize: context.awikiResponsive.displayScaled(18),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: context.awikiResponsive.spacing(8)),
          Text(
            subtitle,
            style: AwikiMeTextStyles.cardSubtitle.copyWith(
              fontSize: context.awikiResponsive.bodySm,
            ),
          ),
        ],
      ),
    );
  }
}

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.titleKey,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.horizontalPadding,
  });

  final String title;
  final Key? titleKey;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final content = Padding(
      padding: responsive.scaledInsets(
        EdgeInsets.symmetric(horizontal: horizontalPadding ?? 16, vertical: 16),
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: responsive.spacing(16)),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  key: titleKey,
                  style: AwikiMeTextStyles.listTitle.copyWith(
                    fontSize: responsive.bodyMd,
                    color: destructive ? theme.danger : theme.title,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: responsive.spacing(2)),
                  Text(
                    subtitle!,
                    style: AwikiMeTextStyles.cardSubtitle.copyWith(
                      fontSize: responsive.bodySm,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: responsive.spacing(12)),
          trailing ??
              AwikiAssetIcon(
                assetName: 'assets/icons/icon_right.svg',
                size: responsive.iconSm,
                color: onTap == null ? theme.border : theme.tertiaryText,
              ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: title,
      borderRadius: BorderRadius.circular(responsive.radius(14)),
      child: content,
    );
  }
}
