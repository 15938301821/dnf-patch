/**
 * @fileoverview 把 Server finalized 质量 DTO 转为三图审查可展示的版本化摘要，并比较两侧摘要。
 *
 * 流程位置：skill-evidence-comparison 先用本模块核对源帧与结果图的摘要，再由 QualityGate
 * 展示同一份证据。输入只来自类型化 jobs API；输出是无副作用 ViewModel 或布尔比较结果。
 * schema 1 是历史参考 RGB；schema 2/3/4 是历史稳定帧质量；schema 5 是当前九项质量。
 * 安全边界：必须先判别 schemaVersion，不能跨版本读取字段，也不能在浏览器重算通过结论。
 */
import type { PatchTaskSkillPreview } from "../../api/index.js";

/** Server 透传、由三图审查消费的 finalized 质量 DTO。 */
export type ReferenceTransferQuality = NonNullable<
  PatchTaskSkillPreview["referenceTransferQuality"]
>;

/** 单项 finalized 指标的展示文本；threshold 只是 Server 规则说明，不是客户端判定结果。 */
export interface QualityEvidenceItem {
  label: string;
  value: string;
  threshold: string;
}

/** QualityGate 消费的纯展示模型，保留 schema 供响应式网格选择正确列数。 */
export interface QualityEvidenceModel {
  schemaVersion: ReferenceTransferQuality["schemaVersion"];
  ariaLabel: string;
  items: readonly QualityEvidenceItem[];
  summary: string;
}

/**
 * 按 DTO 版本构造 finalized 质量摘要，不跨版本读取字段或自行判断是否通过。
 *
 * @param quality Server 随源帧或结果图返回、且已通过双侧一致性检查的质量 DTO。
 * @returns 当前 schema 的指标、服务端门槛说明和样本计数。
 */
export function createQualityEvidenceModel(
  quality: ReferenceTransferQuality,
): QualityEvidenceModel {
  const sampleSummary = `${quality.evaluatedFrameCount.toLocaleString("zh-CN")} 帧 · ${quality.evaluatedPixelCount.toLocaleString("zh-CN")} 有效像素`;

  switch (quality.schemaVersion) {
    case 1:
      return {
        schemaVersion: 1,
        ariaLabel: "参考图传输质量门禁",
        items: [
          {
            label: "参考覆盖率",
            value: percent(quality.referenceCoverage),
            threshold: "门槛 ≥ 80%",
          },
          {
            label: "RGB 相似度",
            value: percent(quality.referenceSimilarity),
            threshold: "门槛 ≥ 90%",
          },
          {
            label: "清晰度倍率",
            value: `${quality.edgeEnergyRatio.toFixed(2)}×`,
            threshold: "门槛 ≥ 1.01×",
          },
        ],
        summary: `历史参考 RGB 门禁 · ${sampleSummary}`,
      };
    case 2:
      return {
        schemaVersion: 2,
        ariaLabel: "历史稳定帧质量门禁",
        items: stableFrameItems(quality),
        summary: `历史稳定帧门禁 · ${sampleSummary}`,
      };
    case 3:
      return {
        schemaVersion: 3,
        ariaLabel: "历史稳定帧质量门禁",
        items: [...stableFrameItems(quality), ...edgePatternItems(quality)],
        summary: `历史稳定帧门禁 · ${sampleSummary}`,
      };
    case 4:
      return {
        schemaVersion: 4,
        ariaLabel: "历史稳定帧质量门禁",
        items: [
          ...stableFrameItems(quality),
          ...edgePatternItems(quality),
          ...compressionRiskItems(quality),
        ],
        summary: `历史稳定帧门禁 · ${sampleSummary}`,
      };
    case 5:
      return {
        schemaVersion: 5,
        ariaLabel: "当前稳定帧质量门禁",
        items: [
          ...stableFrameItems(quality),
          ...edgePatternItems(quality),
          ...compressionRiskItems(quality),
          {
            label: "官方能量拓扑相关性",
            value: percent(quality.sourceTopologyCorrelation),
            threshold: "单帧最坏值 ≥ 65%",
          },
        ],
        summary: `当前稳定帧门禁 · ${sampleSummary}`,
      };
  }
}

/**
 * 严格比较源帧和结果图的 finalized 质量摘要，避免展示单侧漂移值。
 *
 * @returns 公共样本计数及当前版本全部质量字段均相同时为 true。
 */
export function sameQuality(
  left: ReferenceTransferQuality,
  right: ReferenceTransferQuality,
): boolean {
  if (left.schemaVersion !== right.schemaVersion) return false;
  if (
    left.evaluatedFrameCount !== right.evaluatedFrameCount ||
    left.evaluatedPixelCount !== right.evaluatedPixelCount
  ) {
    return false;
  }

  switch (left.schemaVersion) {
    case 1:
      return (
        right.schemaVersion === 1 &&
        left.referenceCoverage === right.referenceCoverage &&
        left.referenceSimilarity === right.referenceSimilarity &&
        left.sourceEdgeEnergy === right.sourceEdgeEnergy &&
        left.runtimeEdgeEnergy === right.runtimeEdgeEnergy &&
        left.edgeEnergyRatio === right.edgeEnergyRatio
      );
    case 2:
      return right.schemaVersion === 2 && sameStableFrameQuality(left, right);
    case 3:
      return (
        right.schemaVersion === 3 &&
        sameStableFrameQuality(left, right) &&
        sameEdgePatternQuality(left, right)
      );
    case 4:
      return (
        right.schemaVersion === 4 &&
        sameStableFrameQuality(left, right) &&
        sameEdgePatternQuality(left, right) &&
        sameCompressionRiskQuality(left, right)
      );
    case 5:
      return (
        right.schemaVersion === 5 &&
        sameStableFrameQuality(left, right) &&
        sameEdgePatternQuality(left, right) &&
        sameCompressionRiskQuality(left, right) &&
        left.sourceTopologyCorrelation === right.sourceTopologyCorrelation
      );
  }
}

type StableFrameQuality = Extract<
  ReferenceTransferQuality,
  { schemaVersion: 2 | 3 | 4 | 5 }
>;
type EdgePatternQuality = Extract<
  ReferenceTransferQuality,
  { schemaVersion: 3 | 4 | 5 }
>;
type CompressionRiskQuality = Extract<
  ReferenceTransferQuality,
  { schemaVersion: 4 | 5 }
>;

/** schema 2-5 共享四项稳定帧指标，但不读取后续版本才有的扩展字段。 */
function stableFrameItems(
  quality: StableFrameQuality,
): readonly QualityEvidenceItem[] {
  return [
    {
      label: "孤立噪点",
      value: percent(quality.isolatedNoiseRatio),
      threshold: "门槛 ≤ 1.5%",
    },
    {
      label: "连续能量带",
      value: percent(quality.continuousBandRatio),
      threshold: "门槛 ≥ 55%",
    },
    {
      label: "亮核占比",
      value: percent(quality.brightCoreRatio),
      threshold: "门槛 ≥ 1%",
    },
    {
      label: quality.schemaVersion === 2 ? "边缘对比" : "锐边对比",
      value: quality.edgeContrast.toFixed(2),
      threshold: "门槛 ≥ 24",
    },
  ];
}

/** schema 3-5 共享强边缘与周期条纹风险指标。 */
function edgePatternItems(
  quality: EdgePatternQuality,
): readonly QualityEvidenceItem[] {
  return [
    {
      label: "强边缘占比",
      value: percent(quality.strongEdgeRatio),
      threshold: "门槛 ≤ 25%",
    },
    {
      label: "周期栅栏",
      value: percent(quality.periodicStripeRatio),
      threshold: "门槛 ≤ 8%",
    },
  ];
}

/** schema 4-5 共享近白线和 DXT1 块边界风险指标。 */
function compressionRiskItems(
  quality: CompressionRiskQuality,
): readonly QualityEvidenceItem[] {
  return [
    {
      label: "近白长线占比",
      value: percent(quality.maximumWhiteLineRatio),
      threshold: "单帧最坏值 ≤ 45%",
    },
    {
      label: "DXT1 边界跳变",
      value: percent(quality.maximumDxt1BoundaryJumpRatio),
      threshold: "单帧最坏值 ≤ 5%",
    },
  ];
}

/** 比较 schema 2-5 共有的四项稳定帧指标。 */
function sameStableFrameQuality(
  left: StableFrameQuality,
  right: StableFrameQuality,
): boolean {
  return (
    left.isolatedNoiseRatio === right.isolatedNoiseRatio &&
    left.continuousBandRatio === right.continuousBandRatio &&
    left.brightCoreRatio === right.brightCoreRatio &&
    left.edgeContrast === right.edgeContrast
  );
}

/** 比较 schema 3-5 共有的条纹与强边缘指标。 */
function sameEdgePatternQuality(
  left: EdgePatternQuality,
  right: EdgePatternQuality,
): boolean {
  return (
    left.strongEdgeRatio === right.strongEdgeRatio &&
    left.periodicStripeRatio === right.periodicStripeRatio
  );
}

/** 比较 schema 4-5 共有的压缩风险指标。 */
function sameCompressionRiskQuality(
  left: CompressionRiskQuality,
  right: CompressionRiskQuality,
): boolean {
  return (
    left.maximumWhiteLineRatio === right.maximumWhiteLineRatio &&
    left.maximumDxt1BoundaryJumpRatio === right.maximumDxt1BoundaryJumpRatio
  );
}

/** 把 0..1 的证据比率格式化为一位百分数，不改变 Server 阈值语义。 */
function percent(value: number): string {
  return new Intl.NumberFormat("zh-CN", {
    style: "percent",
    maximumFractionDigits: 1,
  }).format(value);
}
