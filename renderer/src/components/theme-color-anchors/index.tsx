/**
 * @fileoverview 编辑主题定义中的命名颜色锚点列表。
 *
 * 共享职业风格表单通过 Ant Design Form.List 渲染本组件，值由父表单拥有并最终进入风格写入
 * DTO；组件只同步颜色选择器和文本框，不发请求。颜色值必须保持 `#RRGGBB`，最多 16 项，
 * 动态增删不能绕过表单校验或共享可变对象。
 */
import { Button, Form, Input } from "antd";
import { Plus, Trash2 } from "lucide-react";
import type { ThemeColorAnchor } from "../../server/contracts.js";
import styles from "./index.module.scss";

/** 颜色选择器与文本输入共享的受控值契约。 */
interface ColorValueInputProps {
  value?: string;
  onChange?: (value: string) => void;
}

/**
 * 同步原生颜色控件和十六进制文本输入。
 *
 * @param props 父级 Form.Item 提供的受控值与变更回调；非法文本仅影响颜色控件回退显示。
 * @returns 两个输入组成的受控字段，不自行提交表单。
 */
function ColorValueInput({
  value = "#000000",
  onChange,
}: ColorValueInputProps): React.JSX.Element {
  const normalized = /^#[A-Fa-f0-9]{6}$/u.test(value) ? value : "#000000";
  return (
    <div className={styles["color-value"]}>
      <input
        aria-label="选择颜色"
        onChange={(event) => onChange?.(event.target.value.toUpperCase())}
        type="color"
        value={normalized}
      />
      <Input
        maxLength={7}
        onChange={(event) => onChange?.(event.target.value.toUpperCase())}
        placeholder="#1A8FFF"
        value={value}
      />
    </div>
  );
}

/**
 * 渲染主题颜色锚点的动态表单列表。
 *
 * @returns 由父级 Ant Design Form 拥有状态的增删界面；组件本身不发请求。
 */
export function ThemeColorAnchors(): React.JSX.Element {
  return (
    <Form.List name={["themeDefinition", "colorAnchors"]}>
      {(fields, { add, remove }) => (
        <div className={styles.field}>
          <div className={styles.heading}>
            <div>
              <strong>颜色锚点</strong>
              <span>最多 16 个命名色值，用于固定主题色板。</span>
            </div>
            <Button
              disabled={fields.length >= 16}
              icon={<Plus size={15} />}
              onClick={() =>
                add({ name: "", value: "#000000" } satisfies ThemeColorAnchor)
              }
              size="small"
            >
              添加颜色
            </Button>
          </div>
          {fields.length === 0 ? (
            <div className={styles.empty}>尚未添加颜色锚点</div>
          ) : (
            <div className={styles.list}>
              {fields.map((field) => (
                <div className={styles.row} key={field.key}>
                  <Form.Item
                    name={[field.name, "name"]}
                    rules={[{ required: true, message: "请输入颜色名称" }]}
                  >
                    <Input maxLength={60} placeholder="冰蓝主光" />
                  </Form.Item>
                  <Form.Item
                    name={[field.name, "value"]}
                    rules={[
                      { required: true, message: "请输入色值" },
                      {
                        pattern: /^#[A-Fa-f0-9]{6}$/u,
                        message: "使用 #RRGGBB 格式",
                      },
                    ]}
                  >
                    <ColorValueInput />
                  </Form.Item>
                  <Button
                    aria-label="删除颜色"
                    icon={<Trash2 size={15} />}
                    onClick={() => remove(field.name)}
                    type="text"
                  />
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </Form.List>
  );
}
