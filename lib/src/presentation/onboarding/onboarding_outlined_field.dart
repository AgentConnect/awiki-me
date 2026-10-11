import 'package:flutter/cupertino.dart';

import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';

/// Shared outlined field for every contact, verification and invitation input.
class OnboardingOutlinedField extends StatefulWidget {
  const OnboardingOutlinedField({
    super.key,
    required this.controller,
    required this.label,
    required this.placeholder,
    this.semanticsIdentifier,
    this.labelHint,
    this.icon,
    this.keyboardType,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final String? semanticsIdentifier;
  final String? labelHint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;

  @override
  State<OnboardingOutlinedField> createState() =>
      _OnboardingOutlinedFieldState();
}

class _OnboardingOutlinedFieldState extends State<OnboardingOutlinedField> {
  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final fontSize = phone ? 16.0 : 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _OnboardingFieldLabel(widget.label, hint: widget.labelHint),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            child: Container(
              constraints: BoxConstraints(minHeight: phone ? 50 : 38),
              padding: phone
                  ? const EdgeInsets.fromLTRB(14, 7, 7, 7)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              // Focus draws an ink edge; the fill stays paper.
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(phone ? 16 : 6),
                border: Border.all(
                  color: _focused ? theme.title : theme.border,
                  width: _focused && phone ? 1.5 : 1,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (widget.prefix != null) ...<Widget>[
                    widget.prefix!,
                    const SizedBox(width: 8),
                    Container(
                      width: phone ? 0.5 : 1,
                      height: 16,
                      color: theme.border,
                    ),
                    const SizedBox(width: 8),
                  ] else if (!phone &&
                      widget.icon == CupertinoIcons.at) ...<Widget>[
                    // Reference desktop fields: a small quiet "@" for the
                    // handle and no glyph for code or email.
                    Text(
                      '@',
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ] else if (phone && widget.icon != null) ...<Widget>[
                    Icon(widget.icon, size: 18, color: theme.secondaryText),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Semantics(
                      identifier: widget.semanticsIdentifier,
                      child: CupertinoTextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        keyboardType: widget.keyboardType,
                        placeholder: widget.placeholder,
                        decoration: null,
                        padding: EdgeInsets.zero,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          color: theme.title,
                          fontSize: fontSize,
                          height: 1.2,
                        ),
                        placeholderStyle: TextStyle(
                          color: theme.secondaryText,
                          fontSize: fontSize,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...<Widget>[
                    const SizedBox(width: 8),
                    widget.suffix!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingFieldLabel extends StatelessWidget {
  const _OnboardingFieldLabel(this.label, {this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: phone ? theme.title : theme.secondaryText,
            fontSize: phone ? 13 : 12,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint!,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: phone ? 11 : 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
