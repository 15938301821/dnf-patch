import type { ModelCapability } from "../../../shared/contracts.js";

interface HeroProps {
  capabilities: readonly ModelCapability[];
}

/** 展示三模型角色与本地静态能力状态，不触发网络探测。 */
export function Hero({ capabilities }: HeroProps): React.JSX.Element {
  return (
    <section className="hero">
      <div>
        <p className="kicker">AUDITABLE VISUAL PATCH PIPELINE</p>
        <h1>
          从设计语义到真实 NPK，
          <span>每一步都可追溯。</span>
        </h1>
        <p className="hero-copy">
          SOL 调度、GPT-5.5 工程设计、gpt-image-2
          参考素材与固定本地工具链共享同一冻结上下文。模型不能选择脚本、资源路径或部署状态。
        </p>
      </div>
      <div className="model-rail">
        {capabilities.map((capability, index) => (
          <div className="model-node" key={capability.role}>
            <span>{String(index + 1).padStart(2, "0")}</span>
            <div>
              <small>{capability.role.toUpperCase()}</small>
              <strong>{capability.requestedModel}</strong>
            </div>
            <i className={capability.available ? "online" : "offline"} />
          </div>
        ))}
      </div>
    </section>
  );
}
