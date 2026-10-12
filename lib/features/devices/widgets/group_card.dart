import 'package:flutter/material.dart';
import '../services/device_groups.dart';
import 'group_style.dart';

const _okColor = Color(0xFF2E7D32);
const _warnColor = Color(0xFFD32F2F);

// การ์ดกลุ่มบนหน้าหลัก: ไอคอน+ชื่อ+จำนวนอุปกรณ์ แถบความชื้นเฉลี่ย และสถานะ
// รวม (ปกติ / n ต้องดู) — กดเพื่อเข้าไปดูอุปกรณ์ในกลุ่ม ความสูงคงที่เพื่อให้ทุก
// ใบในกริดเท่ากัน ไม่ว่าชื่อจะสั้น/ยาว
class GroupCard extends StatelessWidget {
  final String name;
  final String iconKey;
  final int colorIndex;
  final GroupStats stats;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.name,
    required this.iconKey,
    required this.colorIndex,
    required this.stats,
    required this.onTap,
  });

  static const height = 148.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final accent = groupColor(colorIndex);
    final avg = stats.avgMoisture;
    final needs = stats.needsAttention;

    return SizedBox(
      height: height,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GroupBadge(
                      iconKey: iconKey,
                      colorIndex: colorIndex,
                      size: 52,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${stats.count} อุปกรณ์",
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      avg == null
                          ? "ความชื้นเฉลี่ย –"
                          : "ความชื้นเฉลี่ย ${avg.toStringAsFixed(0)}%",
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _StatusPill(needs: needs, total: stats.count),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ((avg ?? 0) / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    color: accent,
                    backgroundColor: scheme.surfaceContainerHighest,
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

class _StatusPill extends StatelessWidget {
  final int needs;
  final int total;

  const _StatusPill({required this.needs, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return Text(
        "ยังไม่มีอุปกรณ์",
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      );
    }
    final bad = needs > 0;
    final color = bad ? _warnColor : _okColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bad ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            bad ? "$needs ต้องดู" : "ปกติ",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
