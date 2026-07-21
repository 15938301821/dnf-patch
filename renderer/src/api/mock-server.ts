import MockAdapter from "axios-mock-adapter";
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
  SaveModelConfigurationInput,
  SaveProfessionStyleInput,
  SessionUser,
} from "./contracts.js";
import {
  initialMockModelConfiguration,
  saveMockModelConfiguration,
} from "./mock-model-configuration.js";
import {
  areSelectedSkillsValid,
  mockProfessionSkills,
  swordSoulCandidateSkillIds,
} from "./mock-profession-skills.js";
import { refreshClient, server } from "./server.js";
import { evaluateSkillExecution } from "../utils/skill-gate.js";

interface MockState {
  professions: ProfessionSummary[];
  skills: ProfessionSkillSummary[];
  styles: ProfessionStyle[];
  jobs: PatchTask[];
  modelConfiguration: ModelConfiguration;
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
  styles: [
    {
      id: "style-vergil",
      professionId: "profession-sword-soul",
      name: "暗蓝幻影",
      description: "冷色剑气、克制高光与清晰的斩击阶段。",
      agent:
        "保持源帧几何、锚点与动作阶段，只调整已授权特效层的色彩、材质和粒子语言。",
      prompt:
        "Deep cobalt sword aura, restrained cyan edge light, crisp directional slash trails, transparent effect layer.",
      selectedSkillIds: swordSoulCandidateSkillIds,
      publishStatus: "private",
      updatedAt: "2026-07-20T08:30:00.000Z",
    },
    {
      id: "style-sakura",
      professionId: "profession-female-nen",
      name: "樱花念气",
      description: "粉白念气与樱花粒子，保留原动作轮廓和透明层语义。",
      agent: "以源帧语义为事实源，樱花材质只作用于已登记的念气特效层。",
      prompt:
        "Soft rose-white nen energy, controlled sakura petals, luminous core, readable silhouette, transparent background.",
      selectedSkillIds: [],
      publishStatus: "published",
      updatedAt: "2026-07-18T09:10:00.000Z",
    },
  ],
  jobs: [
    {
      id: "job-demo-complete",
      professionName: "气功师（女）",
      styleName: "樱花念气",
      status: "passed",
      progress: 100,
      createdAt: "2026-07-20T07:40:00.000Z",
      artifactName: "mock-sakura-preview.txt",
      downloadUrl: "/jobs/job-demo-complete/artifact",
    },
  ],
  modelConfiguration: initialMockModelConfiguration,
};

let state: MockState = structuredClone(initialState);
let sessionActive = false;

function envelope<T>(data: T): ApiEnvelope<T> {
  return { data };
}

function parseBody(body: string | undefined): unknown {
  return JSON.parse(body ?? "{}") as unknown;
}

function now(): string {
  return new Date().toISOString();
}

function id(prefix: string): string {
  return `${prefix}-${crypto.randomUUID()}`;
}

function session(): AuthSession {
  return { accessToken: `mock.${crypto.randomUUID()}`, user };
}

function recalculateStyleCount(professionId: string): void {
  const profession = state.professions.find((item) => item.id === professionId);
  if (profession) {
    profession.styleCount = state.styles.filter(
      (style) => style.professionId === professionId,
    ).length;
    profession.updatedAt = now();
  }
}

export function configureMockApi(): void {
  const mock = new MockAdapter(server, { delayResponse: 280 });
  const refreshMock = new MockAdapter(refreshClient, { delayResponse: 120 });

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

  mock
    .onGet("/users/me/model-configuration")
    .reply(() => [200, envelope(state.modelConfiguration)]);
  mock.onPut("/users/me/model-configuration").reply((config) => {
    const input = parseBody(
      config.data as string | undefined,
    ) as SaveModelConfigurationInput;
    state.modelConfiguration = saveMockModelConfiguration(
      input,
      state.modelConfiguration,
    );
    return [200, envelope(state.modelConfiguration)];
  });

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
        style.selectedSkillIds.length === 0,
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
    Object.assign(style, input, { updatedAt: now() });
    return [200, envelope(style)];
  });
  mock
    .onPost(/\/professions\/[^/]+\/styles\/[^/]+\/review$/u)
    .reply((config) => {
      const parts = config.url?.split("/") ?? [];
      const style = state.styles.find((item) => item.id === parts[4]);
      if (!style) {
        return [404, { code: "STYLE_NOT_FOUND", message: "职业风格不存在。" }];
      }
      style.publishStatus = "pending";
      style.updatedAt = now();
      return [200, envelope(style)];
    });

  mock.onGet("/jobs").reply(() => [200, envelope(state.jobs)]);
  mock.onPost("/jobs").reply((config) => {
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
      artifactName: `mock-${profession.slug}-${style.id}.txt`,
      downloadUrl: "pending",
    };
    job.downloadUrl = `/jobs/${job.id}/artifact`;
    state.jobs.unshift(job);
    return [201, envelope(job)];
  });
  mock.onGet(/\/jobs\/[^/]+\/artifact$/u).reply((config) => {
    const jobId = config.url?.split("/")[2] ?? "";
    const job = state.jobs.find((item) => item.id === jobId);
    if (!job) {
      return [404, "Not found"];
    }
    const content = [
      "DNF Patch Studio mock artifact",
      `job=${job.id}`,
      `profession=${job.professionName}`,
      `style=${job.styleName}`,
      "This file proves only the frontend download flow.",
    ].join("\n");
    return [200, new Blob([content], { type: "text/plain;charset=utf-8" })];
  });

  mock.onPost("/__mock/reset").reply(() => {
    state = structuredClone(initialState);
    sessionActive = false;
    return [200, envelope(null)];
  });
}
