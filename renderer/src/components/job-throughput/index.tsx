/**
 * @fileoverview 展示单个制作任务的大模型吞吐摘要、真实 Token/s 趋势、分组与最近调用账本。
 *
 * 任务详情页传入服务端聚合的脱敏 ViewModel，本组件只格式化和展示，不发模型/API 请求、不读取
 * 凭据或 Provider 响应正文。nullable 计量始终显示“未计量”，不能替换为零；成功率与计量覆盖率
 * 使用不同分母，分开呈现以避免误导任务观察者。
 */
import { Tag } from "antd";
import type { PatchTaskModelThroughput } from "../../server/contracts.js";
import {
  formatJobDateTime,
  formatMeasuredDecimal,
  formatMeasuredInteger,
  formatProviderLatency,
  modelCallStatusView,
  modelRoleView,
} from "../../config/job-detail-view.js";
import { ThroughputChart } from "./throughput-chart.js";
import styles from "./index.module.scss";

/** 吞吐展示组件的受控输入；数据必须来自当前任务详情响应。 */
interface JobThroughputProps {
  throughput: PatchTaskModelThroughput;
}

/**
 * 渲染模型吞吐监控面板。
 * @param props 当前任务的服务端聚合计量和最多 60 条最近调用。
 * @returns 汇总、趋势、模型分组和最近八条调用；不产生网络或计时器副作用。
 */
export function JobThroughput({
  throughput,
}: JobThroughputProps): React.JSX.Element {
  const maxGroupRate = Math.max(
    ...throughput.groups.map(
      (group) => group.averageOutputTokensPerSecond ?? 0,
    ),
    1,
  );
  const recentCalls = throughput.recentCalls.slice(-8).reverse();

  return (
    <section
      aria-labelledby="model-throughput-heading"
      className={styles.section}
    >
      <header className={styles.header}>
        <div>
          <span className={styles.eyebrow}>MODEL TELEMETRY</span>
          <h2 id="model-throughput-heading">大模型吞吐</h2>
        </div>
        <span className={styles["call-count"]}>
          {throughput.runningCalls > 0
            ? `${String(throughput.runningCalls)} 个调用进行中`
            : `${String(throughput.totalCalls)} 个调用`}
        </span>
      </header>

      <div className={styles.metrics}>
        <Metric
          label="平均输出吞吐"
          unit={
            throughput.averageOutputTokensPerSecond === null ? "" : "Token/s"
          }
          value={formatMeasuredDecimal(throughput.averageOutputTokensPerSecond)}
        />
        <Metric
          label="累计输出 Token"
          value={formatMeasuredInteger(throughput.outputTokens)}
        />
        <Metric
          label="Provider 平均耗时"
          value={formatProviderLatency(throughput.averageProviderLatencyMs)}
        />
        <Metric
          label="计量覆盖"
          unit="次出站"
          value={`${String(throughput.measuredCalls)} / ${String(throughput.egressCalls)}`}
        />
        <Metric
          label="调用成功率"
          unit={throughput.successRate === null ? "" : "%"}
          value={formatMeasuredDecimal(throughput.successRate)}
        />
      </div>

      <div className={styles.dashboard}>
        <div className={styles.trend}>
          <div className={styles["subheading-row"]}>
            <h3>输出 Token/s 趋势</h3>
            <span>最近 {throughput.recentCalls.length} 条审计调用</span>
          </div>
          <ThroughputChart calls={throughput.recentCalls} />
        </div>

        <aside aria-label="模型吞吐分组" className={styles.groups}>
          <div className={styles["subheading-row"]}>
            <h3>模型分组</h3>
            <span>按角色 / 模型</span>
          </div>
          {throughput.groups.length === 0 ? (
            <div className={styles["groups-empty"]}>暂无模型调用</div>
          ) : (
            throughput.groups.map((group) => {
              const rate = group.averageOutputTokensPerSecond;
              return (
                <div
                  className={styles.group}
                  key={`${group.role}:${group.model}`}
                >
                  <div className={styles["group-name"]}>
                    <i
                      style={{
                        backgroundColor: modelRoleView[group.role].color,
                      }}
                    />
                    <div>
                      <strong>{modelRoleView[group.role].label}</strong>
                      <span>{group.model}</span>
                    </div>
                    <b>
                      {rate === null
                        ? "未计量"
                        : `${formatMeasuredDecimal(rate)} /s`}
                    </b>
                  </div>
                  <div className={styles["group-bar"]}>
                    <i
                      style={{
                        backgroundColor: modelRoleView[group.role].color,
                        width: `${String(rate === null ? 0 : Math.max((rate / maxGroupRate) * 100, 4))}%`,
                      }}
                    />
                  </div>
                  <span className={styles["group-meta"]}>
                    {group.measuredCalls} / {group.calls} 次计量 · 输出{" "}
                    {formatMeasuredInteger(group.outputTokens)}
                  </span>
                </div>
              );
            })
          )}
        </aside>
      </div>

      <div className={styles.ledger}>
        <div className={styles["subheading-row"]}>
          <h3>最近调用</h3>
          <span>Provider 边界计量</span>
        </div>
        <div className={styles["table-scroll"]}>
          <table>
            <thead>
              <tr>
                <th>时间</th>
                <th>角色 / 模型</th>
                <th>状态</th>
                <th>输出 Token</th>
                <th>Provider 耗时</th>
                <th>吞吐</th>
              </tr>
            </thead>
            <tbody>
              {recentCalls.length === 0 ? (
                <tr>
                  <td className={styles["empty-cell"]} colSpan={6}>
                    暂无模型调用审计
                  </td>
                </tr>
              ) : (
                recentCalls.map((call) => (
                  <tr key={call.id}>
                    <td>
                      <time dateTime={call.createdAt}>
                        {formatJobDateTime(call.createdAt)}
                      </time>
                    </td>
                    <td>
                      <div className={styles["model-cell"]}>
                        <i
                          style={{
                            backgroundColor: modelRoleView[call.role].color,
                          }}
                        />
                        <span>
                          <strong>{modelRoleView[call.role].label}</strong>
                          <small>{call.model}</small>
                        </span>
                      </div>
                    </td>
                    <td>
                      <Tag color={modelCallStatusView[call.status].color}>
                        {modelCallStatusView[call.status].label}
                      </Tag>
                    </td>
                    <td>{formatMeasuredInteger(call.outputTokens)}</td>
                    <td>{formatProviderLatency(call.providerLatencyMs)}</td>
                    <td className={styles.rate}>
                      {call.outputTokensPerSecond === null
                        ? "未计量"
                        : `${formatMeasuredDecimal(call.outputTokensPerSecond)} /s`}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

/** 渲染固定高度的单项汇总，异步刷新数字不会改变指标网格尺寸。 */
function Metric({
  label,
  value,
  unit = "",
}: {
  label: string;
  value: string;
  unit?: string;
}): React.JSX.Element {
  return (
    <div className={styles.metric}>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{unit}</small>
    </div>
  );
}
