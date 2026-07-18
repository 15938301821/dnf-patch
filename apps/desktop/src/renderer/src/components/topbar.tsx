/** 应用品牌与不可提升的安全状态提示。 */
export function Topbar(): React.JSX.Element {
  return (
    <header className="topbar">
      <div className="brand">
        <span className="brand-mark">DP</span>
        <span>
          <strong>DNF Patch Studio</strong>
          <small>Agentic production control plane</small>
        </span>
      </div>
      <div className="safety-chip">
        <span className="safety-dot" />
        部署永久禁用 · 证据优先
      </div>
    </header>
  );
}
