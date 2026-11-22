import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'pace_ui.dart';

/// Cartão padrão com cantos arredondados e espaçamento interno.
class PaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const PaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color;
    if (c == null) {
      // Padrão do app: vidro fumê.
      return GlassCard(padding: padding, onTap: onTap, radius: 22, child: child);
    }
    final p = Pal.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: p.shadow),
      child: Card(
        color: c,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Valor grande com rótulo pequeno embaixo.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? color;
  final bool large;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: numStyle(large ? 30 : 22, color: color ?? Theme.of(context).colorScheme.onSurface),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(unit!, style: t.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: muted),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: muted)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Grade de [StatTile] em colunas.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double spacing;

  const StatGrid({super.key, required this.children, this.columns = 3, this.spacing = 16});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final row = <Widget>[];
      for (var j = 0; j < columns; j++) {
        final k = i + j;
        if (j > 0) row.add(const SizedBox(width: 10));
        row.add(Expanded(child: k < children.length ? children[k] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: row));
    }
    return Column(children: rows);
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: numStyle(18, color: Theme.of(context).colorScheme.onSurface))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Estado vazio que orienta o próximo passo.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  /// Ilustração no lugar do ícone (ex.: o mascote).
  final Widget? art;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
    this.art,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          art ??
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 36, color: cs.primary),
              ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...actions.map((a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: a)),
          ],
        ],
      ),
    );
  }
}

/// Selo de variação (+12% / −5%) com cor.
class ChangeBadge extends StatelessWidget {
  final double? ratio;
  final bool higherIsBetter;
  final String suffix;

  const ChangeBadge({super.key, required this.ratio, this.higherIsBetter = true, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final r = ratio;
    if (r == null) return const SizedBox.shrink();
    final v = (r * 100).round();
    final good = higherIsBetter ? v > 0 : v < 0;
    final neutral = v == 0;
    final cs = Theme.of(context).colorScheme;
    final color = neutral ? cs.onSurfaceVariant : (good ? Pal.of(context).mintText : const Color(0xFFDC2626));
    final icon = neutral ? Icons.remove : (v > 0 ? Icons.arrow_upward : Icons.arrow_downward);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text('${v.abs()}%$suffix', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirmar',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}
