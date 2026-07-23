/**
 * @fileoverview 把当前职业风格草稿投影为只读模拟预览。
 *
 * 风格编辑页传入本地草稿 ViewModel，组件展示固定参考图、主题摘录和状态；不读取 Store、
 * 不发请求，也不声称图片是后端生成产物。空文本使用界面回退值，动态内容必须被布局截断，
 * 避免长 Prompt 改变工作区尺寸。
 */
import { Image, Tag } from "antd";
import { Eye, FileText, Palette, ShieldCheck } from "lucide-react";
import previewImage from "../../assets/style-preview.png";
import type { ProfessionStyle } from "../../server/contracts.js";
import { PublishStatus } from "../publish-status/index.js";
import styles from "./index.module.scss";

/** 预览所需的最小脱敏风格字段，不包含职业资源或任务数据。 */
interface StylePreviewProps {
  style: Pick<
    ProfessionStyle,
    | "name"
    | "description"
    | "themeDefinition"
    | "skillPrompts"
    | "publishStatus"
  >;
}

/** 返回去除空白后的草稿文本，空值则使用仅供展示的占位文案。 */
function excerpt(value: string, fallback: string): string {
  const normalized = value.trim();
  return normalized || fallback;
}

/**
 * 展示当前草稿的模拟视觉摘要。
 *
 * @param props 风格编辑页提供的受控草稿片段；内容可能尚未满足送审门禁。
 * @returns 固定参考图与主题摘要，不产生网络或状态写入副作用。
 */
export function StylePreview({ style }: StylePreviewProps): React.JSX.Element {
  return (
    <section className={styles.preview}>
      <header className={styles.header}>
        <div>
          <Eye aria-hidden="true" size={18} />
          <span>实时预览</span>
        </div>
        <Tag color="warning">模拟</Tag>
      </header>

      <figure className={styles.figure}>
        <div className={styles["image-frame"]}>
          <Image
            alt="剑魂风格参考图"
            className={styles.image ?? ""}
            preview={{ mask: "查看原图" }}
            src={previewImage}
          />
        </div>
        <figcaption>
          <PublishStatus status={style.publishStatus} />
          <h2>{excerpt(style.name, "未命名风格")}</h2>
          <p>{excerpt(style.description, "填写描述后将在这里实时显示。")}</p>
        </figcaption>
      </figure>

      <div className={styles.evidence}>
        <article>
          <ShieldCheck aria-hidden="true" size={17} />
          <div>
            <strong>主题目标</strong>
            <p>{excerpt(style.themeDefinition.goal, "尚未填写主题目标。")}</p>
          </div>
        </article>
        <article>
          <FileText aria-hidden="true" size={17} />
          <div>
            <strong>共同视觉基线</strong>
            <p>
              {excerpt(
                style.themeDefinition.baseStyle,
                "尚未填写共同视觉基线。",
              )}
            </p>
          </div>
        </article>
        <article>
          <Palette aria-hidden="true" size={17} />
          <div>
            <strong>色板与技能增量</strong>
            <p>
              {style.themeDefinition.colorAnchors.length} 个颜色锚点，
              {style.skillPrompts.length} 个技能主题草稿。
            </p>
          </div>
        </article>
      </div>
    </section>
  );
}
