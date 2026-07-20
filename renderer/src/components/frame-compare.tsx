interface FrameCompareProps {
  sourceLabel: string;
  outputLabel: string;
}

/** 帧对照占位视图只表达证据槽位，不伪造未加载的像素预览。 */
export function FrameCompare({
  sourceLabel,
  outputLabel,
}: FrameCompareProps): React.JSX.Element {
  return (
    <div className="frame-compare">
      <div>
        <span>SOURCE</span>
        <strong>{sourceLabel}</strong>
      </div>
      <div>
        <span>RUNTIME</span>
        <strong>{outputLabel}</strong>
      </div>
    </div>
  );
}
