/**
 * @fileoverview 提供职业、技能目录和职业风格的类型化 HTTP API。
 *
 * 职业/风格页面通过共享受认证 Axios 客户端调用；输入是后端稳定 ID 与结构化写入 DTO，
 * 输出为服务端事实或界面 ViewModel。模块不发现技能、不推断资源映射，旧风格仅在读取列表
 * 时规范化；保存、送审错误由页面处理，最终授权与完整性仍由后端决定。
 */
import type {
  CreateProfessionInput,
  CreateProfessionStyleInput,
  ProfessionSkillSummary,
  ProfessionStyle,
  ProfessionSummary,
  SaveProfessionStyleInput,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";
import { normalizeProfessionStyle } from "../utils/profession-style.js";

/** @returns `GET /professions` 返回的当前用户职业摘要列表。 */
export function getProfessionsList(): Promise<ProfessionSummary[]> {
  return requestData<ProfessionSummary[]>({
    method: "GET",
    url: "/professions",
  });
}

/**
 * 通过 `POST /professions` 创建职业记录。
 *
 * @param input 已校验的名称与稳定 slug，不包含技能或本机资源信息。
 * @returns 服务端创建的职业摘要。
 */
export function createProfession(
  input: CreateProfessionInput,
): Promise<ProfessionSummary> {
  return requestData<ProfessionSummary>({
    method: "POST",
    url: "/professions",
    data: input,
  });
}

/**
 * 通过 `GET /professions/:professionId/skills` 读取服务端技能事实目录。
 *
 * @param professionId 路由或职业列表提供的后端稳定 ID。
 * @returns 技能摘要；空列表表示目录不可用，不能由客户端补造。
 */
export function getProfessionSkills(
  professionId: string,
): Promise<ProfessionSkillSummary[]> {
  return requestData<ProfessionSkillSummary[]>({
    method: "GET",
    url: `/professions/${professionId}/skills`,
  });
}

/**
 * 通过 `GET /professions/:professionId/styles` 读取并规范化职业风格。
 *
 * @param professionId 当前选中职业的后端稳定 ID。
 * @returns 可供页面消费的当前结构列表；旧响应只映射公共主题层。
 */
export function getProfessionStyles(
  professionId: string,
): Promise<ProfessionStyle[]> {
  return requestData<ProfessionStyle[]>({
    method: "GET",
    url: `/professions/${professionId}/styles`,
  }).then((styles) => styles.map(normalizeProfessionStyle));
}

/**
 * 通过 `POST /professions/:professionId/styles` 创建私有风格草稿。
 *
 * @param professionId 当前职业的后端稳定 ID。
 * @param input 表单生成的结构化主题与逐技能写入 DTO，可在门禁允许范围内不完整。
 * @returns 服务端创建的风格；请求不创建制作任务。
 */
export function createProfessionStyle(
  professionId: string,
  input: CreateProfessionStyleInput,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "POST",
    url: `/professions/${professionId}/styles`,
    data: input,
  });
}

/**
 * 通过 `PUT /professions/:professionId/styles/:styleId` 保存当前草稿。
 *
 * @param professionId 路由中的职业稳定 ID。
 * @param styleId 路由中的风格稳定 ID，必须属于该职业。
 * @param input 当前受控表单的完整结构化写入 DTO。
 * @returns 服务端保存后的风格；不隐式送审或创建任务。
 */
export function saveProfessionStyle(
  professionId: string,
  styleId: string,
  input: SaveProfessionStyleInput,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "PUT",
    url: `/professions/${professionId}/styles/${styleId}`,
    data: input,
  });
}

/**
 * 通过 `POST /professions/:professionId/styles/:styleId/review` 提交审核。
 *
 * @param professionId 当前风格所属职业的稳定 ID。
 * @param styleId 已先成功保存且通过客户端完整性门禁的风格 ID。
 * @returns 服务端更新后的风格；客户端前置检查不替代后端审核门禁。
 */
export function submitStyleForReview(
  professionId: string,
  styleId: string,
): Promise<ProfessionStyle> {
  return requestData<ProfessionStyle>({
    method: "POST",
    url: `/professions/${professionId}/styles/${styleId}/review`,
  });
}
