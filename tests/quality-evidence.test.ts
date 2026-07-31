/**
 * @fileoverview 回归三图 finalized 质量摘要的 V1-V5 严格比较与无字段越界格式化。
 *
 * 测试直接调用无副作用 ViewModel 函数，不引入 React 渲染依赖；它保护历史 schema 可读性，
 * 并验证当前 V5 九项指标全部参与一致性比较。这里只验证前端 DTO 消费边界。
 */
import { describe, expect, it } from "vitest";
import {
  createQualityEvidenceModel,
  sameQuality,
  type ReferenceTransferQuality,
} from "../renderer/src/components/skill-evidence-comparison/quality-evidence.js";

const qualityV1 = {
  schemaVersion: 1,
  evaluatedFrameCount: 40,
  evaluatedPixelCount: 28_640,
  referenceCoverage: 0.96,
  referenceSimilarity: 0.94,
  sourceEdgeEnergy: 18.4,
  runtimeEdgeEnergy: 23.1,
  edgeEnergyRatio: 1.255,
} satisfies ReferenceTransferQuality;

const qualityV2 = {
  schemaVersion: 2,
  evaluatedFrameCount: 40,
  evaluatedPixelCount: 28_640,
  isolatedNoiseRatio: 0.005,
  continuousBandRatio: 0.78,
  brightCoreRatio: 0.08,
  edgeContrast: 72,
} satisfies ReferenceTransferQuality;

const qualityV3 = {
  ...qualityV2,
  schemaVersion: 3,
  strongEdgeRatio: 0.12,
  periodicStripeRatio: 0,
} satisfies ReferenceTransferQuality;

const qualityV4 = {
  ...qualityV3,
  schemaVersion: 4,
  maximumWhiteLineRatio: 0.34,
  maximumDxt1BoundaryJumpRatio: 0.01,
} satisfies ReferenceTransferQuality;

const qualityV5 = {
  ...qualityV4,
  schemaVersion: 5,
  sourceTopologyCorrelation: 0.9,
} satisfies ReferenceTransferQuality;

describe("quality evidence", () => {
  it("不同 schema 的 finalized 摘要不相等", () => {
    expect(sameQuality(qualityV1, qualityV2)).toBe(false);
    expect(sameQuality(qualityV2, qualityV3)).toBe(false);
    expect(sameQuality(qualityV3, qualityV4)).toBe(false);
    expect(sameQuality(qualityV4, qualityV5)).toBe(false);
  });

  it.each([
    ["evaluatedFrameCount", { evaluatedFrameCount: 41 }],
    ["evaluatedPixelCount", { evaluatedPixelCount: 28_641 }],
    ["referenceCoverage", { referenceCoverage: 0.95 }],
    ["referenceSimilarity", { referenceSimilarity: 0.93 }],
    ["sourceEdgeEnergy", { sourceEdgeEnergy: 18.5 }],
    ["runtimeEdgeEnergy", { runtimeEdgeEnergy: 23.2 }],
    ["edgeEnergyRatio", { edgeEnergyRatio: 1.256 }],
  ] as const)("V1 的 %s 漂移时摘要不相等", (_field, drift) => {
    expect(sameQuality(qualityV1, { ...qualityV1, ...drift })).toBe(false);
  });

  it("历史 V2 只格式化四项稳定帧指标", () => {
    const model = createQualityEvidenceModel(qualityV2);

    expect(model.schemaVersion).toBe(2);
    expect(model.ariaLabel).toBe("历史稳定帧质量门禁");
    expect(model.items.map((item) => item.label)).toEqual([
      "孤立噪点",
      "连续能量带",
      "亮核占比",
      "边缘对比",
    ]);
  });

  it.each([
    ["isolatedNoiseRatio", { isolatedNoiseRatio: 0.006 }],
    ["continuousBandRatio", { continuousBandRatio: 0.79 }],
    ["brightCoreRatio", { brightCoreRatio: 0.09 }],
    ["edgeContrast", { edgeContrast: 73 }],
  ] as const)("V2 的 %s 漂移时摘要不相等", (_field, drift) => {
    expect(sameQuality(qualityV2, { ...qualityV2, ...drift })).toBe(false);
  });

  it.each([
    ["strongEdgeRatio", { strongEdgeRatio: 0.13 }],
    ["periodicStripeRatio", { periodicStripeRatio: 0.01 }],
  ] as const)("V3 的 %s 漂移时摘要不相等", (_field, drift) => {
    expect(sameQuality(qualityV3, { ...qualityV3, ...drift })).toBe(false);
  });

  it("V3 展示六项历史稳定帧指标", () => {
    const model = createQualityEvidenceModel(qualityV3);

    expect(model.items).toHaveLength(6);
    expect(model.items.map((item) => item.label)).toEqual([
      "孤立噪点",
      "连续能量带",
      "亮核占比",
      "锐边对比",
      "强边缘占比",
      "周期栅栏",
    ]);
  });

  it.each([
    ["maximumWhiteLineRatio", { maximumWhiteLineRatio: 0.35 }],
    ["maximumDxt1BoundaryJumpRatio", { maximumDxt1BoundaryJumpRatio: 0.02 }],
  ] as const)("V4 的 %s 漂移时摘要不相等", (_field, drift) => {
    expect(sameQuality(qualityV4, { ...qualityV4, ...drift })).toBe(false);
  });

  it("V4 保持八项历史证据可读", () => {
    const model = createQualityEvidenceModel(qualityV4);

    expect(model.schemaVersion).toBe(4);
    expect(model.ariaLabel).toBe("历史稳定帧质量门禁");
    expect(model.items).toHaveLength(8);
  });

  it.each([
    ["isolatedNoiseRatio", { isolatedNoiseRatio: 0.006 }],
    ["continuousBandRatio", { continuousBandRatio: 0.79 }],
    ["brightCoreRatio", { brightCoreRatio: 0.09 }],
    ["edgeContrast", { edgeContrast: 73 }],
    ["strongEdgeRatio", { strongEdgeRatio: 0.13 }],
    ["periodicStripeRatio", { periodicStripeRatio: 0.01 }],
    ["maximumWhiteLineRatio", { maximumWhiteLineRatio: 0.35 }],
    ["maximumDxt1BoundaryJumpRatio", { maximumDxt1BoundaryJumpRatio: 0.02 }],
    ["sourceTopologyCorrelation", { sourceTopologyCorrelation: 0.89 }],
  ] as const)("V5 的 %s 漂移时摘要不相等", (_field, drift) => {
    expect(sameQuality(qualityV5, { ...qualityV5, ...drift })).toBe(false);
  });

  it("V5 展示当前九项稳定帧指标和拓扑门槛", () => {
    const model = createQualityEvidenceModel(qualityV5);

    expect(sameQuality(qualityV5, { ...qualityV5 })).toBe(true);
    expect(model.schemaVersion).toBe(5);
    expect(model.ariaLabel).toBe("当前稳定帧质量门禁");
    expect(model.items).toHaveLength(9);
    expect(model.items.map((item) => item.label)).toEqual([
      "孤立噪点",
      "连续能量带",
      "亮核占比",
      "锐边对比",
      "强边缘占比",
      "周期栅栏",
      "近白长线占比",
      "DXT1 边界跳变",
      "官方能量拓扑相关性",
    ]);
    expect(model.items.at(-1)).toEqual({
      label: "官方能量拓扑相关性",
      value: "90%",
      threshold: "单帧最坏值 ≥ 65%",
    });
    expect(model.summary).toContain("当前稳定帧门禁");
  });
});
