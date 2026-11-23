import 'pace_ui.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import 'common.dart';
import 'route_widgets.dart';

/// Cartão de corrida com miniatura do percurso (Início).
class ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback? onTap;

  const ActivityCard({super.key, required this.activity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final t = glassTheme.textTheme;
    final cs = glassTheme.colorScheme;
    return PaceCard(
      onTap: onTap,
      child: Row(
        children: [
          RouteThumbnail(points: a.previewPoints, size: 84),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${Fmt.date(a.start)} · ${Fmt.time(a.start)}',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (a.isBike) ...[
                      Icon(Icons.directions_bike_rounded, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 5),
                    ],
                    Flexible(child: Text(a.type, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 10),
                StatGrid(columns: 3, spacing: 8, children: [
                  StatTile(label: 'km', value: Fmt.km(a.distanceM)),
                  StatTile(label: 'tempo', value: Fmt.duration(a.movingSec)),
                  a.isBike
                      ? StatTile(label: 'km/h', value: Fmt.kmh(a.kmh))
                      : StatTile(label: '/km', value: Fmt.pace(a.paceSecPerKm)),
                ]),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Linha compacta do histórico.
class ActivityListTile extends StatelessWidget {
  final Activity activity;
  final VoidCallback? onTap;

  const ActivityListTile({super.key, required this.activity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            RouteThumbnail(points: a.previewPoints, size: 52, strokeWidth: 2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(Fmt.kmUnit(a.distanceM),
                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      if (a.isBike) ...[
                        Icon(Icons.directions_bike_rounded, size: 15, color: cs.primary),
                        const SizedBox(width: 3),
                      ],
                      if (a.source != ActivitySource.recorded)
                        Icon(Icons.file_download_outlined, size: 14, color: cs.onSurfaceVariant),
                      if (a.gpsPartial) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.gps_off, size: 14, color: cs.onSurfaceVariant),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.date(a.start)} · ${Fmt.time(a.start)} · ${a.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.duration(a.movingSec), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(Fmt.effort(a.paceSecPerKm, bike: a.isBike), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
