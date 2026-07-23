/**
 * @fileoverview 查询并触发服务端资源导入流程的类型化 HTTP API。
 *
 * 设置页通过受认证 Axios 客户端调用，输入不包含文件路径，输出仅为后端状态与任务摘要；
 * 浏览器不读取游戏目录、不解析 NPK/IMG，也不执行 Worker。请求成功只代表后端接受或报告
 * 状态，不证明真实资源、数据库或 Worker 集成可用。
 */
import type {
  ResourceImportJob,
  ResourceImportOverview,
} from "../server/contracts.js";
import { requestData } from "../server/server.js";

/**
 * 通过 `GET /resource-imports/overview` 读取服务端资源导入摘要。
 *
 * @returns 不含绝对路径的状态 ViewModel；配置与执行事实由后端拥有。
 */
export function getResourceImportOverview(): Promise<ResourceImportOverview> {
  return requestData<ResourceImportOverview>({
    method: "GET",
    url: "/resource-imports/overview",
  });
}

/**
 * 通过 `POST /resource-imports/jobs` 请求后端排队一次资源导入。
 *
 * @returns 后端接受的任务摘要；未配置或门禁失败时拒绝且客户端不得自行执行导入。
 */
export function createResourceImportJob(): Promise<ResourceImportJob> {
  return requestData<ResourceImportJob>({
    method: "POST",
    url: "/resource-imports/jobs",
  });
}
