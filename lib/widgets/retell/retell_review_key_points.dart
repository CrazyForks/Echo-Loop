/// 复述评估「要点覆盖」小节的统计条与要点卡。
///
/// 纯展示层：只吃一条（可能仍在流式增长的）[RetellReviewKeyPoint]，不读 provider、
/// 不发起副作用。摘录为空的行整行略去，缺什么由首行的判定胶囊说明。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/retell_review_evaluation.dart';
import '../../theme/app_theme.dart';
import 'retell_review_rating_style.dart';

/// 按状态聚合的计数，挂在小节标题右侧，不额外占一行。
///
/// 用和要点卡完全相同的状态图标，而不是抽象色点：色点只有颜色一个维度，
/// 同色的「偏差」和「多说」在统计条里分不出，用户也没法把它和卡片对上。
class RetellReviewStatusTally extends StatelessWidget {
  final List<RetellReviewKeyPoint> keyPoints;

  const RetellReviewStatusTally({required this.keyPoints});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final counts = <RetellReviewKeyPointStatus, int>{};
    for (final item in keyPoints) {
      final status = item.status;
      if (status != null) counts[status] = (counts[status] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.s + 2,
      runSpacing: AppSpacing.xs,
      children: [
        // 固定按 covered→partial→missed→distorted→added 顺序，避免逐帧到达时跳动。
        for (final status in RetellReviewKeyPointStatus.values)
          if (counts[status] != null)
            _TallyItem(status: status, count: counts[status]!, l10n: l10n),
      ],
    );
  }
}

class _TallyItem extends StatelessWidget {
  final RetellReviewKeyPointStatus status;
  final int count;
  final AppLocalizations l10n;

  const _TallyItem({
    required this.status,
    required this.count,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final visual = retellKeyPointVisual(context, l10n, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(visual.icon, size: 14, color: visual.color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$count ${visual.label}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 单条要点卡：首行是要点本身与判定状态，其后逐行给「原文 / 你说 / 提示」。
///
/// 一条一张卡，而不是所有条目共用一个分组容器：卡内本身就有分行细线，外层若再
/// 用分隔线区分条目，两级线粗细相近，读起来分不出哪条是条目边界。
///
/// 首行放母语要点陈述而不是原文摘录：要点是 schema 里唯一必填的文本，且脱离
/// 摘录也能看懂；原文摘录只是定位依据，`status == added` 时本就不存在，退成
/// 可选的附属行。
class RetellReviewKeyPointCard extends StatelessWidget {
  final RetellReviewKeyPoint keyPoint;

  const RetellReviewKeyPointCard({required this.keyPoint});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visual = retellKeyPointVisual(context, l10n, keyPoint.status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.s + 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      decoration: retellCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyPointHeadRow(visual: visual, text: keyPoint.keyPoint),
          // 摘录为空的行整行不出现：`added` 没有原文、`missed` 没有转录，判定胶囊
          // 已经把这件事说清楚了，再留一行「无」只是多一行要读的空信息。
          if (keyPoint.original.isNotEmpty) ...[
            const _KeyPointRowDivider(),
            _KeyPointFactRow(
              label: l10n.retellAiReviewLabelOriginal,
              text: keyPoint.original,
            ),
          ],
          if (keyPoint.transcript.isNotEmpty) ...[
            const _KeyPointRowDivider(),
            _KeyPointFactRow(
              label: l10n.retellAiReviewLabelYouSaid,
              text: keyPoint.transcript,
            ),
          ],
          if (keyPoint.feedback.isNotEmpty) ...[
            const _KeyPointRowDivider(),
            _KeyPointFactRow(
              label: l10n.retellAiReviewLabelTip,
              text: keyPoint.feedback,
            ),
          ],
        ],
      ),
    );
  }
}

/// 要点卡首行：状态图标 + 状态胶囊（覆盖 / 部分 / 遗漏 / 偏差 / 多说）+ 要点陈述。
///
/// 胶囊位置原先放的是中性的「要点」标签——那个词不带信息，而判定只由一个图标承担，
/// 用户看不懂五个图标分别是什么。把判定文案顶到这里，图标与文字同色互为注解，
/// 卡片仍只有这一处彩色。
class _KeyPointHeadRow extends StatelessWidget {
  final RetellKeyPointVisual visual;

  /// 母语要点陈述；调用方保证非空（报告只渲染已成形的条目）。
  final String text;

  const _KeyPointHeadRow({required this.visual, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(visual.icon, size: 20, color: visual.color),
          ),
          const SizedBox(width: AppSpacing.s + 2),
          Expanded(
            child: _KeyPointLabelledText(
              label: visual.label,
              labelColor: visual.color,
              filled: true,
              text: text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「标签 + 正文」的一行文本，标签用 [WidgetSpan] 内联进正文段首。
///
/// 标签不单独占一列：中文标签只有两个字，定宽标签列会在标签和正文之间留出一大
/// 片空白，读起来两边断开。内联后正文紧跟标签，回行时顶到标签左边缘，卡内四行
/// 也是同一个结构。
class _KeyPointLabelledText extends StatelessWidget {
  final String label;

  /// 标签颜色；[filled] 为 true 时同色淡染做底。
  final Color labelColor;

  /// 标签是否带淡染底（见 [_KeyPointLabelChip]）。
  final bool filled;

  final String text;
  final TextStyle? style;

  const _KeyPointLabelledText({
    required this.label,
    required this.labelColor,
    required this.filled,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s),
            child: _KeyPointLabelChip(
              label: label,
              color: labelColor,
              filled: filled,
            ),
          ),
        ),
        TextSpan(text: text, style: style),
      ],
    ),
  );
}

/// 行首的标签：只做身份标识。
///
/// [filled] 为 true 才是胶囊（语义色淡染底 + 同色文字），留给首行的判定状态；
/// 「原文 / 你说 / 提示」这类中性标签一律 false，退成纯文字。中性标签本来也顶着
/// 一个灰底小方块，一张卡里四个灰块加起来就把首行那个唯一该抢眼的判定盖过去了。
class _KeyPointLabelChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _KeyPointLabelChip({
    required this.label,
    required this.color,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: color,
        // 无底色时靠字距把标签和紧跟的正文拉开，否则两段文字会糊成一句。
        letterSpacing: filled ? null : .3,
      ),
    );
    if (!filled) return text;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s - 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: text,
    );
  }
}

/// 要点卡的附属行：内联标签 + 内容，整行中性色。
///
/// 不带图标也不带语义色：一张卡里唯一该抢注意力的是首行的判定状态图标，附属行
/// 再各配一个彩色图标，四种颜色平摊下来状态反而看不见了。行与行的身份由无底色的
/// 标签文字区分就够，缩进对齐首行正文，读起来仍是同一列。
class _KeyPointFactRow extends StatelessWidget {
  final String label;

  /// 摘录正文；调用方保证非空，空行由调用方整行略去。
  final String text;

  const _KeyPointFactRow({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: _factRowIndent,
        top: AppSpacing.s + 2,
        bottom: AppSpacing.s + 2,
      ),
      child: _KeyPointLabelledText(
        label: label,
        labelColor: theme.colorScheme.onSurfaceVariant,
        filled: false,
        text: text,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 附属行左缩进：与首行状态图标（20）+ 图标到正文的间距（10）对齐。
const _factRowIndent = 20.0 + AppSpacing.s + 2;

/// 要点卡内的分行细线，比条目之间的间距更弱，只用来分「事实 / 判定」几段。
class _KeyPointRowDivider extends StatelessWidget {
  const _KeyPointRowDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .32),
  );
}
