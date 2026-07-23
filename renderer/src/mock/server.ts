/** @fileoverview 为显式 Mock 模式安装同 DTO 和门禁语义的内存 Axios 替身；不证明真实 Server、数据库、Worker、模型或对象存储可用，也不得存储真实凭据。 */
import MockAdapter from "axios-mock-adapter";
import { AxiosHeaders } from "axios";
import type {
  ApiEnvelope,
  AuthSession,
  CreatePatchTaskInput,
  CreateProfessionInput,
  CreateProfessionStyleInput,
  LoginInput,
  ModelConfiguration,
  PatchTask,
  ProfessionSkillSummary,
  ProfessionStyle,
  ProfessionSummary,
  ResourceImportJob,
  ResourceImportOverview,
  SaveModelConfigurationInput,
  SaveProfessionStyleInput,
  SessionUser,
} from "../server/contracts.js";
import { refreshClient, server } from "../server/server.js";
import { evaluateSkillExecution } from "../utils/skill-gate.js";
import {
  evaluateStyleCompleteness,
  evaluateStyleDraftValidity,
} from "../utils/style-completeness.js";
import { initialMockModelConfiguration } from "./model-configuration.js";
import {
  areSelectedSkillsValid,
  mockProfessionSkills,
} from "./profession-skills.js";
import { initialMockProfessionStyles } from "./profession-styles.js";

interface MockState {
  professions: ProfessionSummary[];
  skills: ProfessionSkillSummary[];
  styles: ProfessionStyle[];
  jobs: PatchTask[];
  modelConfiguration: ModelConfiguration;
  resourceImport: ResourceImportOverview;
}

const user: SessionUser = {
  id: "user-demo",
  username: "demo",
  displayName: "演示用户",
};

const initialState: MockState = {
  professions: [
    {
      id: "profession-sword-soul",
      name: "剑魂",
      slug: "sword-soul",
      styleCount: 1,
      publishStatus: "private",
      updatedAt: "2026-07-20T08:30:00.000Z",
    },
    {
      id: "profession-berserker",
      name: "狂战士",
      slug: "berserker",
      styleCount: 0,
      publishStatus: "private",
      updatedAt: "2026-07-19T14:20:00.000Z",
    },
    {
      id: "profession-female-nen",
      name: "气功师（女）",
      slug: "female-nen-master",
      styleCount: 1,
      publishStatus: "published",
      updatedAt: "2026-07-18T09:10:00.000Z",
    },
  ],
  skills: mockProfessionSkills,
  styles: initialMockProfessionStyles,
  jobs: [
    {
      id: "job-demo-complete",
      professionName: "气功师（女）",
      styleName: "樱花念气",
      status: "passed",
      progress: 100,
      createdAt: "2026-07-20T07:40:00.000Z",
      artifactName: "mock-sakura-preview.bpk",
      artifactAvailable: true,
    },
  ],
  modelConfiguration: initialMockModelConfiguration,
  resourceImport: {
    mode: "server-mirror",
    status: "idle",
    resourceVersion: "mock-2026-07-20",
    resourceRootConfigured: true,
    lastImportedAt: "2026-07-20T06:30:00.000Z",
    lastJobId: "resource-import-demo",
    message:
      "Mock 后端已配置只读资源镜像；真实环境由 Worker 读取 GAME_RESOURCE_ROOT 并解析入库。",
  },
};

let state: MockState = structuredClone(initialState);
let sessionActive = false;

/** 用正式 API 的成功包络包装一份 Mock 响应数据。 */
function envelope<T>(data: T): ApiEnvelope<T> {
  return { data };
}
/** 解析 Axios Mock 收到的 JSON 请求体；无请求体时使用空对象。 */
function parseBody(body: string | undefined): unknown {
  return JSON.parse(body ?? "{}") as unknown;
}
/** @returns 当前时刻的 ISO 字符串，用于内存演示记录。 */
function now(): string {
  return new Date().toISOString();
}
/** 使用领域前缀和随机 UUID 生成本次 Mock 进程内的记录 ID。 */
function id(prefix: string): string {
  return `${prefix}-${crypto.randomUUID()}`;
}
/** 创建不含真实凭据、仅供 Mock 请求链使用的临时会话 DTO。 */
function session(): AuthSession {
  return { accessToken: `mock.${crypto.randomUUID()}`, user };
}
/** 在 Mock 风格集合变化后同步对应职业的派生计数与更新时间。 */
function recalculateStyleCount(professionId: string): void {
  const profession = state.professions.find((item) => item.id === professionId);
  if (profession) {
    profession.styleCount = state.styles.filter(
      (style) => style.professionId === professionId,
    ).length;
    profession.updatedAt = now();
  }
}

/** 在两个 Axios 客户端上安装内存路由；不返回值，重置端点仅供测试隔离。 */
export function configureMockApi(): void {
  const mock = new MockAdapter(server, { delayResponse: 280 });
  const refreshMock = new MockAdapter(refreshClient, { delayResponse: 120 });

  // 第一步：模拟登录、当前用户、登出和 Cookie 刷新语义，不保存真实凭据。
  mock.onPost("/auth/login").reply((config) => {
    const input = parseBody(config.data as string | undefined) as LoginInput;
    if (!input.username.trim() || !input.password) {
      return [
        400,
        { code: "LOGIN_INPUT_INVALID", message: "请输入账号和密码。" },
      ];
    }
    sessionActive = true;
    return [200, envelope(session())];
  });
  // 第二步：模型读取保持脱敏，写入只记录是否曾提供 Key，不保留明文。
  mock
    .onGet("/auth/me")
    .reply(() =>
      sessionActive
        ? [200, envelope(user)]
        : [401, { code: "SESSION_REQUIRED", message: "请先登录。" }],
    );
  mock.onPost("/auth/logout").reply(() => {
    sessionActive = false;
    return [200, envelope(null)];
  });
  refreshMock
    .onPost("/auth/refresh")
    .reply(() =>
      sessionActive
        ? [200, envelope(session())]
        : [401, { code: "REFRESH_TOKEN_INVALID", message: "会话已失效。" }],
    );

  // 第三步：资源导入只改变内存任务状态，不访问游戏目录或启动 Worker。
  mock
    .onGet("/users/me/model-configuration")
    .reply(() => [200, envelope(state.modelConfiguration)]);
  /** 校验首次配置的 Key 存在性，并只保存脱敏后的密钥存在状态。 */
  mock.onPut("/users/me/model-configuration").reply((config) => {
    const input = parseBody(
      config.data as string | undefined,
    ) as SaveModelConfigurationInput;
    const roles = [
      "orchestrator",
      "spriteProcessor",
      "referenceGenerator",
    ] as const;
    if (
      roles.some(
        (role) =>
          !state.modelConfiguration[role].keyConfigured && !input[role].apiKey,
      )
    ) {
      return [
        400,
        {
          code: "MODEL_API_KEY_REQUIRED",
          message: "首次配置每个模型角色时都必须填写 API Key。",
        },
      ];
    }
    state.modelConfiguration = {
      orchestrator: mockSavedRole("orchestrator", input),
      spriteProcessor: mockSavedRole("spriteProcessor", input),
      referenceGenerator: mockSavedRole("referenceGenerator", input),
    };
    return [200, envelope(state.modelConfiguration)];
  });

  mock
    .onGet("/resource-imports/overview")
    .reply(() => [200, envelope(state.resourceImport)]);
  /** 在资源根已配置时创建内存排队记录，否则按正式错误语义拒绝。 */
  mock.onPost("/resource-imports/jobs").reply(() => {
    if (!state.resourceImport.resourceRootConfigured) {
      return [
        409,
        {
          code: "RESOURCE_ROOT_NOT_CONFIGURED",
          message: "后端尚未配置只读游戏资源根目录。",
        },
      ];
    }
    const job: ResourceImportJob = {
      id: id("resource-import"),
      mode: state.resourceImport.mode,
      status: "queued",
      createdAt: now(),
    };
    state.resourceImport = {
      ...state.resourceImport,
      status: "queued",
      lastJobId: job.id,
      message:
        "资源导入任务已排队；真实环境将由后端 Worker 解析并写入技能事实源。",
    };
    return [201, envelope(job)];
  });

  // 第四步：职业、技能和风格路由复用正式 DTO，并执行草稿与送审门禁。
  mock.onGet("/professions").reply(() => [200, envelope(state.professions)]);
  mock.onPost("/professions").reply((config) => {
    const input = parseBody(
      config.data as string | undefined,
    ) as CreateProfessionInput;
    const profession: ProfessionSummary = {
      id: id("profession"),
      name: input.name.trim(),
      slug: input.slug.trim(),
      styleCount: 0,
      publishStatus: "private",
      updatedAt: now(),
    };
    state.professions.unshift(profession);
    return [201, envelope(profession)];
  });

  mock.onGet(/\/professions\/[^/]+\/skills$/u).reply((config) => {
    const professionId = config.url?.split("/")[2] ?? "";
    return [
      200,
      envelope(
        state.skills.filter((skill) => skill.professionId === professionId),
      ),
    ];
  });

  mock.onGet(/\/professions\/[^/]+\/styles$/u).reply((config) => {
    const professionId = config.url?.split("/")[2] ?? "";
    return [
      200,
      envelope(
        state.styles.filter((style) => style.professionId === professionId),
      ),
    ];
  });
  /** 校验技能集合与草稿结构后创建私有风格，不触发审核或制作。 */
  mock.onPost(/\/professions\/[^/]+\/styles$/u).reply((config) => {
    const professionId = config.url?.split("/")[2] ?? "";
    const input = parseBody(
      config.data as string | undefined,
    ) as CreateProfessionStyleInput;
    if (
      !areSelectedSkillsValid(
        state.skills,
        professionId,
        input.selectedSkillIds,
        true,
      )
    ) {
      return [
        400,
        {
          code: "STYLE_SKILLS_INVALID",
          message: "请选择当前职业技能目录中的至少一个技能。",
        },
      ];
    }
    const draftValidity = evaluateStyleDraftValidity(input);
    if (!draftValidity.allowed) {
      return [
        400,
        {
          code: "STYLE_CONTENT_INVALID",
          message:
            draftValidity.reasons[0] === "prompt-package-too-large"
              ? "主题 Prompt 包超过 48 KiB 限制。"
              : "逐技能主题内容必须与所选技能一一对应。",
        },
      ];
    }
    const style: ProfessionStyle = {
      id: id("style"),
      professionId,
      ...input,
      publishStatus: "private",
      updatedAt: now(),
    };
    state.styles.unshift(style);
    recalculateStyleCount(professionId);
    return [201, envelope(style)];
  });
  /** 在目标风格存在且草稿有效时原位更新内存记录。 */
  mock.onPut(/\/professions\/[^/]+\/styles\/[^/]+$/u).reply((config) => {
    const parts = config.url?.split("/") ?? [];
    const style = state.styles.find((item) => item.id === parts[4]);
    if (!style) {
      return [404, { code: "STYLE_NOT_FOUND", message: "职业风格不存在。" }];
    }
    const input = parseBody(
      config.data as string | undefined,
    ) as SaveProfessionStyleInput;
    if (
      !areSelectedSkillsValid(
        state.skills,
        style.professionId,
        input.selectedSkillIds,
        true,
      )
    ) {
      return [
        400,
        {
          code: "STYLE_SKILLS_INVALID",
          message: "请选择当前职业技能目录中的至少一个技能。",
        },
      ];
    }
    const draftValidity = evaluateStyleDraftValidity(input);
    if (!draftValidity.allowed) {
      return [
        400,
        {
          code: "STYLE_CONTENT_INVALID",
          message:
            draftValidity.reasons[0] === "prompt-package-too-large"
              ? "主题 Prompt 包超过 48 KiB 限制。"
              : "逐技能主题内容必须与所选技能一一对应。",
        },
      ];
    }
    Object.assign(style, input, { updatedAt: now() });
    return [200, envelope(style)];
  });
  /** 仅完整风格可转为待审核状态，缺失内容保持失败关闭。 */
  mock
    .onPost(/\/professions\/[^/]+\/styles\/[^/]+\/review$/u)
    .reply((config) => {
      const parts = config.url?.split("/") ?? [];
      const style = state.styles.find((item) => item.id === parts[4]);
      if (!style) {
        return [404, { code: "STYLE_NOT_FOUND", message: "职业风格不存在。" }];
      }
      if (!evaluateStyleCompleteness(style).allowed) {
        return [
          409,
          {
            code: "STYLE_CONTENT_INCOMPLETE",
            message: "主题公共规则或逐技能主题内容尚未完整。",
          },
        ];
      }
      style.publishStatus = "pending";
      style.updatedAt = now();
      return [200, envelope(style)];
    });

  // 第五步：任务路由校验幂等键和资源门禁，但只生成演示元数据，不制作产物。
  mock.onGet("/jobs").reply(() => [200, envelope(state.jobs)]);
  /** 依次校验幂等键、主体关系、内容和资源门禁后生成演示任务。 */
  mock.onPost("/jobs").reply((config) => {
    const idempotencyKey =
      config.headers instanceof AxiosHeaders
        ? config.headers.get("Idempotency-Key")
        : undefined;
    if (
      typeof idempotencyKey !== "string" ||
      !/^[A-Za-z0-9]+(?:[._:-][A-Za-z0-9]+)*$/u.test(idempotencyKey)
    ) {
      return [
        400,
        {
          code: "IDEMPOTENCY_KEY_INVALID",
          message: "Idempotency-Key 请求头缺失或格式无效。",
        },
      ];
    }
    const input = parseBody(
      config.data as string | undefined,
    ) as CreatePatchTaskInput;
    const profession = state.professions.find(
      (item) => item.id === input.professionId,
    );
    const style = state.styles.find((item) => item.id === input.styleId);
    if (!profession || !style || style.professionId !== profession.id) {
      return [400, { code: "JOB_INPUT_INVALID", message: "职业或风格无效。" }];
    }
    if (!evaluateStyleCompleteness(style).allowed) {
      return [
        409,
        {
          code: "STYLE_CONTENT_INCOMPLETE",
          message: "主题公共规则或逐技能主题内容尚未完整。",
        },
      ];
    }
    const executionGate = evaluateSkillExecution(
      style.selectedSkillIds,
      state.skills.filter((skill) => skill.professionId === profession.id),
    );
    if (!executionGate.allowed) {
      return [
        409,
        {
          code: "STYLE_SKILLS_NOT_BUILD_READY",
          message:
            executionGate.reason === "resources-unverified"
              ? "所选技能的资源映射尚未核验，仅可保存设计稿。"
              : "风格缺少可执行的技能范围。",
        },
      ];
    }
    const job: PatchTask = {
      id: id("job"),
      professionName: profession.name,
      styleName: style.name,
      status: "passed",
      progress: 100,
      createdAt: now(),
      artifactName: `mock-${profession.slug}-${style.id}.bpk`,
      artifactAvailable: true,
    };
    state.jobs.unshift(job);
    return [201, envelope(job)];
  });
  /** 为已有 Mock 任务返回固定元数据引用，不提供实际下载字节。 */
  mock.onGet(/\/jobs\/[^/]+\/artifact$/u).reply((config) => {
    const jobId = config.url?.split("/")[2] ?? "";
    const job = state.jobs.find((item) => item.id === jobId);
    if (!job) {
      return [404, "Not found"];
    }
    return [
      200,
      envelope({
        artifactName: job.artifactName ?? `${job.id}.bpk`,
        storageKey: `mock-artifacts/${job.id}/${job.artifactName ?? `${job.id}.bpk`}`,
        mediaType: "application/octet-stream",
        byteLength: 512,
        sha256: "A".repeat(64),
      }),
    ];
  });

  mock.onPost("/__mock/reset").reply(() => {
    state = structuredClone(initialState);
    sessionActive = false;
    return [200, envelope(null)];
  });
}

/** 把模型写入 DTO 映射为不含 Key 的 Mock 读取 ViewModel。 */
function mockSavedRole(
  role: keyof ModelConfiguration,
  input: SaveModelConfigurationInput,
): ModelConfiguration[keyof ModelConfiguration] {
  return {
    endpoint: input[role].endpoint,
    model: input[role].model,
    keyConfigured:
      state.modelConfiguration[role].keyConfigured ||
      Boolean(input[role].apiKey),
  };
}
