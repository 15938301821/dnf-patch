interface ProgressRingProps {
  value: number;
  label: string;
}

/** 纯 CSS 进度环；数值仅表示当前列表完成比例，不提升发布状态。 */
export function ProgressRing({
  value,
  label,
}: ProgressRingProps): React.JSX.Element {
  const bounded = Math.max(0, Math.min(100, Math.round(value)));
  return (
    <div
      aria-label={`${label} ${String(bounded)}%`}
      className="progress-ring"
      style={
        { "--progress": `${String(bounded * 3.6)}deg` } as React.CSSProperties
      }
    >
      <span>{bounded}%</span>
      <small>{label}</small>
    </div>
  );
}
