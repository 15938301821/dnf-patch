/**
 * @fileoverview 把任务最近模型调用中的真实 Token/s 计量绘制为响应式 SVG 趋势图。
 *
 * JobThroughput 传入服务端有序审计样本，本组件只读取非 null 吞吐并按调用时间缩放坐标；
 * 无网络、状态或 DOM 写入副作用。未计量调用不会进入曲线，也不会被替换为零；图例颜色只区分
 * 固定模型角色，原生 SVG title 为每个数据点提供键盘外的补充读数。
 */
import type { PatchTaskModelCallSample } from "../../server/contracts.js";
import {
  formatJobDateTime,
  modelRoleView,
} from "../../config/job-detail-view.js";
import styles from "./throughput-chart.module.scss";

interface ThroughputChartProps {
  calls: PatchTaskModelCallSample[];
}

interface ChartPoint {
  call: PatchTaskModelCallSample;
  value: number;
  x: number;
  y: number;
}

const chart = {
  width: 720,
  height: 230,
  left: 54,
  right: 22,
  top: 18,
  bottom: 38,
};

/**
 * 绘制最近模型调用的输出 Token/s 趋势。
 * @param props 服务端按时间升序返回的最近调用；可能混有未计量或未出站样本。
 * @returns 有计量时返回 SVG 曲线与角色图例，否则返回明确的未计量空状态。
 */
export function ThroughputChart({
  calls,
}: ThroughputChartProps): React.JSX.Element {
  const measured = calls
    .filter(
      (
        call,
      ): call is PatchTaskModelCallSample & {
        outputTokensPerSecond: number;
      } => call.outputTokensPerSecond !== null,
    )
    .map((call) => ({ call, value: call.outputTokensPerSecond }));
  if (measured.length === 0) {
    return (
      <div className={styles["chart-empty"]}>
        <strong>暂无可绘制计量</strong>
        <span>Provider 尚未返回完整 Token usage 与调用耗时。</span>
      </div>
    );
  }

  const plotWidth = chart.width - chart.left - chart.right;
  const plotHeight = chart.height - chart.top - chart.bottom;
  const timestamps = measured.map(({ call }) =>
    new Date(call.createdAt).getTime(),
  );
  const firstTime = Math.min(...timestamps);
  const lastTime = Math.max(...timestamps);
  const timeRange = Math.max(lastTime - firstTime, 1);
  const maxValue = Math.max(...measured.map(({ value }) => value), 1);
  const points: ChartPoint[] = measured.map(({ call, value }) => ({
    call,
    value,
    x:
      measured.length === 1
        ? chart.left + plotWidth / 2
        : chart.left +
          ((new Date(call.createdAt).getTime() - firstTime) / timeRange) *
            plotWidth,
    y: chart.top + plotHeight - (value / maxValue) * plotHeight,
  }));
  const linePath = points
    .map((point, index) =>
      [index === 0 ? "M" : "L", point.x, point.y].join(" "),
    )
    .join(" ");
  const areaPath = [
    linePath,
    "L",
    points.at(-1)?.x ?? chart.left,
    chart.top + plotHeight,
    "L",
    points[0]?.x ?? chart.left,
    chart.top + plotHeight,
    "Z",
  ].join(" ");
  const usedRoles = [...new Set(points.map(({ call }) => call.role))];

  return (
    <div className={styles["chart-wrap"]}>
      <svg
        aria-labelledby="job-throughput-title job-throughput-description"
        className={styles.chart}
        role="img"
        viewBox={[0, 0, chart.width, chart.height].join(" ")}
      >
        <title id="job-throughput-title">模型输出吞吐趋势</title>
        <desc id="job-throughput-description">
          仅包含 Provider 返回完整 Token usage 和耗时的调用，纵轴单位为每秒输出
          Token。
        </desc>
        {[0, 0.25, 0.5, 0.75, 1].map((ratio) => {
          const y = chart.top + plotHeight - ratio * plotHeight;
          return (
            <g key={ratio}>
              <line
                className={styles["grid-line"]}
                x1={chart.left}
                x2={chart.left + plotWidth}
                y1={y}
                y2={y}
              />
              <text
                className={styles["axis-label"]}
                x={chart.left - 10}
                y={y + 4}
              >
                {Math.round(maxValue * ratio)}
              </text>
            </g>
          );
        })}
        <path className={styles["area-path"]} d={areaPath} />
        {points.length > 1 ? (
          <path className={styles["line-path"]} d={linePath} />
        ) : null}
        {points.map((point) => (
          <circle
            className={styles.point}
            cx={point.x}
            cy={point.y}
            fill={modelRoleView[point.call.role].color}
            key={point.call.id}
            r={5}
          >
            <title>{`${modelRoleView[point.call.role].label} · ${point.value.toLocaleString("zh-CN", { maximumFractionDigits: 1 })} Token/s · ${formatJobDateTime(point.call.createdAt)}`}</title>
          </circle>
        ))}
        <text
          className={styles["axis-caption"]}
          x={chart.left}
          y={chart.height - 8}
        >
          {formatJobDateTime(measured[0]?.call.createdAt ?? "")}
        </text>
        <text
          className={styles["axis-caption-end"]}
          x={chart.left + plotWidth}
          y={chart.height - 8}
        >
          {formatJobDateTime(measured.at(-1)?.call.createdAt ?? "")}
        </text>
        <text className={styles["axis-unit"]} x={chart.left} y={12}>
          Token/s
        </text>
      </svg>
      <div aria-label="模型角色图例" className={styles.legend}>
        {usedRoles.map((role) => (
          <span key={role}>
            <i style={{ backgroundColor: modelRoleView[role].color }} />
            {modelRoleView[role].label}
          </span>
        ))}
      </div>
    </div>
  );
}
