/**
 * @fileoverview 验证 V6 逐帧详情的中文阶段和帧准备摘要能进入静态 DOM。
 *
 * React 服务端静态渲染替代真实浏览器与后端，只证明组件消费 ViewModel 后的可见文案；不证明
 * 响应式像素布局、网络读取、Artifact 内容、目标图生成、候选 NPK 或部署能力。
 */
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { JobSkillProgress } from "../renderer/src/components/job-skill-progress/index.js";
import type { PatchTaskSkillProgress } from "../renderer/src/server/contracts.js";

describe("V6 job detail view", () => {
  it("renders target-frame stages and frozen source counts", () => {
    const skill: PatchTaskSkillProgress = {
      skillId: "11111111-1111-4111-8111-111111111111",
      displayName: "技术组件 illusionslash",
      status: "blocked",
      errorCode: "PROFESSION_TARGET_FRAME_EXECUTION_UNAVAILABLE",
      stages: [
        { key: "target-manifest", status: "passed" },
        { key: "source-frame-freeze", status: "passed" },
        { key: "target-frame-generation", status: "blocked" },
        { key: "runtime-validation", status: "pending" },
      ],
      referenceImageAvailable: false,
      framePreparation: {
        targetFrameCount: 211,
        generationFrameCount: 211,
        sourceFrameCount: 211,
      },
    };

    const markup = renderToStaticMarkup(
      createElement(JobSkillProgress, {
        skills: [skill],
        onCompareEvidence: () => undefined,
      }),
    );

    expect(markup).toContain("目标清单");
    expect(markup).toContain("源帧冻结");
    expect(markup).toContain("目标帧生成");
    expect(markup).toContain("源帧 211 / 211");
    expect(markup).toContain("清单 211 帧");
    expect(markup).toContain("PROFESSION_TARGET_FRAME_EXECUTION_UNAVAILABLE");
  });
});
