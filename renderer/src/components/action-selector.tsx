import type { PipelineAction } from "../../../server/shared/contracts.js";
import { ACTIONS } from "../config/actions.js";

interface ActionSelectorProps {
  action: PipelineAction;
  onChange: (action: PipelineAction) => void;
}

/** 生产动作选择器；只改变本地表单，不会直接启动 Run。 */
export function ActionSelector({
  action,
  onChange,
}: ActionSelectorProps): React.JSX.Element {
  return (
    <section className="action-grid" aria-label="生产动作">
      {ACTIONS.map((item) => (
        <button
          className={action === item.id ? "action-card active" : "action-card"}
          key={item.id}
          onClick={() => onChange(item.id)}
          type="button"
        >
          <small>{item.eyebrow}</small>
          <strong>{item.title}</strong>
          <span>{item.description}</span>
          <b>→</b>
        </button>
      ))}
    </section>
  );
}
