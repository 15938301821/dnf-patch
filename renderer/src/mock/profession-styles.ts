/**
 * @fileoverview 提供 Mock 模式启动时使用的固定职业风格演示数据。
 *
 * Mock Server 克隆本数组后供页面读取和修改；数据只用于前端交互与测试，不代表公共模板、
 * 真实资源映射或后端发布状态。所有技能引用来自相邻 Mock 技能目录，不产生外部副作用。
 */
import type {
  ProfessionStyle,
  SkillThemePrompt,
  ThemeDefinition,
} from "../server/contracts.js";
import { swordSoulCandidateSkillIds } from "./profession-skills.js";

const vergilTheme: ThemeDefinition = {
  schemaVersion: 1,
  goal: "保持剑魂动作与阶段语义，追加暗蓝幻影、次元裂隙与冷色剑气。",
  baseStyle:
    "DMC5 Vergil aesthetic, icy cobalt-blue energy, clean sharp blade edges, controlled action-game VFX layering",
  colorAnchors: [
    { name: "冰蓝主光", value: "#1A8FFF" },
    { name: "暗底辉光", value: "#0A1633" },
    { name: "刀刃高光", value: "#FFFFFF" },
    { name: "空间裂纹", value: "#00D4FF" },
  ],
  materialRules: "白色锐利刃核配合冰蓝外辉光，裂纹保持青色硬边。",
  particleRules: "粒子保持稀疏、方向明确，使用冰晶或故障冰尾迹。",
  layeringRules: "空间裂纹在后，剑刃与幻影剑居中，辉光和粒子在前。",
  constraints: "保持源帧几何、锚点与动作阶段，只调整已授权特效层的视觉语言。",
  acceptanceCriteria: "冷蓝层级清楚，动作轮廓、运动方向和命中焦点保持可读。",
  exclusions: "排除暖色火光、杂乱粒子、无关 UI、文字与水印。",
};

const sakuraTheme: ThemeDefinition = {
  schemaVersion: 1,
  goal: "用粉白念气和樱花粒子表现柔和主题，同时保留原技能辨识。",
  baseStyle:
    "sakura petals, rose-pink energy, pink-white highlights, translucent floral mist",
  colorAnchors: [
    { name: "深紫红", value: "#3A0D25" },
    { name: "樱花粉", value: "#FFB7C5" },
    { name: "粉白高光", value: "#FFF5F8" },
  ],
  materialRules: "高亮区使用粉白，主体使用樱花粉，暗部保留深紫红层次。",
  particleRules: "花瓣、雾、金边和光尘按技能阶段克制使用。",
  layeringRules: "念气主体优先，花瓣和透明花雾不能遮蔽运动中心。",
  constraints: "以源帧语义为事实源，只处理后端已登记的念气特效层。",
  acceptanceCriteria: "各阶段连续可见，技能运动方向、轮廓和命中辨识不变。",
  exclusions: "排除全画布黑块、空起手、人物误染和静态粉色光团。",
};

/** 每次 Mock 重置时克隆的初始风格集合，调用方不得直接作为可变运行状态复用。 */
export const initialMockProfessionStyles: ProfessionStyle[] = [
  {
    id: "style-vergil",
    professionId: "profession-sword-soul",
    name: "暗蓝幻影",
    description: "冷色剑气、克制高光与清晰的斩击阶段。",
    themeDefinition: vergilTheme,
    selectedSkillIds: swordSoulCandidateSkillIds,
    skillPrompts: swordSoulCandidateSkillIds.map(createVergilSkillPrompt),
    publishStatus: "private",
    updatedAt: "2026-07-20T08:30:00.000Z",
  },
  {
    id: "style-sakura",
    professionId: "profession-female-nen",
    name: "樱花念气",
    description: "粉白念气与樱花粒子，保留原动作轮廓和透明层语义。",
    themeDefinition: sakuraTheme,
    selectedSkillIds: [],
    skillPrompts: [],
    publishStatus: "published",
    updatedAt: "2026-07-18T09:10:00.000Z",
  },
];

/** 为一个 Mock 技能稳定 ID 生成独立的暗蓝主题增量。 */
function createVergilSkillPrompt(skillId: string): SkillThemePrompt {
  return {
    skillId,
    themePrompt:
      "icy-blue dimensional slash language with restrained particles",
    changes: "在职业动作骨架不变的前提下追加冷蓝剑气与空间裂纹。",
    acceptanceCriteria: "主题外观不能遮蔽该技能的运动方向和命中焦点。",
    exclusions: "排除暖色、无关元素和改变职业动作的构图。",
  };
}
