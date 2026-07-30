/**
 * @fileoverview 定义三图审查固定角色的顺序与只读展示文案。
 *
 * SkillEvidenceComparison 和单项面板共同消费这些配置；角色值来自 Server DTO，不能由界面
 * 扩展为任意 Artifact 查询。模块只输出静态配置，无网络、状态或浏览器副作用。
 */
import type { PatchTaskSkillPreviewRole } from "../../api/index.js";

/** Server 允许浏览器请求的三个固定预览角色，顺序也是桌面与移动审查顺序。 */
export const previewRoles = [
  "source-frame",
  "reference-image",
  "aseprite-result",
] as const satisfies readonly PatchTaskSkillPreviewRole[];

/** 单个固定角色的界面标题、角标及来源边界说明。 */
export interface PreviewRoleView {
  order: string;
  title: string;
  shortTitle: string;
  badge: string;
  description: string;
}

/** 三个固定角色的只读展示配置；文案不改变 Server/Worker 的证据语义。 */
export const previewRoleView: Record<
  PatchTaskSkillPreviewRole,
  PreviewRoleView
> = {
  "source-frame": {
    order: "01",
    title: "技能源帧",
    shortTitle: "源帧",
    badge: "官方约束",
    description: "已核验资源中的代表帧",
  },
  "reference-image": {
    order: "02",
    title: "模型参考图",
    shortTitle: "模型参考",
    badge: "风格与构图参考",
    description: "图片模型提供视觉方向，不直接决定最终像素",
  },
  "aseprite-result": {
    order: "03",
    title: "模型 + Aseprite 结果",
    shortTitle: "Aseprite 结果",
    badge: "受控重建",
    description: "在官方帧结构内受控重建可见 RGB，并恢复尺寸、位置与 Alpha",
  },
};
