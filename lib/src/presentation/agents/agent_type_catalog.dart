import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import '../../domain/entities/agent/agent_command.dart';

/// Presentation of supported products, independent of host capabilities and
/// installation status. Protocol/runtime identifiers stay in the domain enum.
abstract final class AgentTypeCatalog {
  static const kinds = RuntimeAgentKind.values;
  static String names(AppLocalizations l10n) => kinds
      .map((k) => k.displayLabel)
      .join(l10n.localeName.startsWith('zh') ? '、' : ', ');
  static String description(AppLocalizations l10n, RuntimeAgentKind kind) =>
      kind == RuntimeAgentKind.hermes
      ? l10n.agentCreateHermesDescription
      : l10n.agentCreateRequiresSignedInCli(kind.displayLabel);
  static String icon(RuntimeAgentKind kind) =>
      'assets/branding/agents/${kind.runtime}.${kind == RuntimeAgentKind.deepseekHarness ? 'svg' : 'png'}';
}

class AgentTypeIcon extends StatelessWidget {
  const AgentTypeIcon({super.key, required this.kind, this.size = 36});
  final RuntimeAgentKind kind;
  final double size;
  @override
  Widget build(BuildContext context) {
    final path = AgentTypeCatalog.icon(kind);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: path.endsWith('.svg')
            ? SvgPicture.asset(path, fit: BoxFit.contain)
            : Image.asset(
                path,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}

/// Seven finite cards: row heights follow their content, never a fixed grid
/// aspect ratio. Large text and narrow windows use one column.
class AgentTypeGrid extends StatelessWidget {
  const AgentTypeGrid({super.key, required this.builder});
  final Widget Function(RuntimeAgentKind kind) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 640 &&
          MediaQuery.textScalerOf(context).scale(14) <= 19.6;
      const kinds = AgentTypeCatalog.kinds;
      if (!twoColumns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final kind in kinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: builder(kind),
              ),
          ],
        );
      }
      return Column(
        children: [
          for (var index = 0; index < kinds.length; index += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: builder(kinds[index])),
                    const SizedBox(width: 10),
                    Expanded(
                      child: index + 1 < kinds.length
                          ? builder(kinds[index + 1])
                          : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
