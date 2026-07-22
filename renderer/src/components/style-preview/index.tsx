import { Image, Tag } from "antd";
import { Eye, FileText, Palette, ShieldCheck } from "lucide-react";
import previewImage from "../../assets/style-preview.png";
import type { ProfessionStyle } from "../../api/contracts.js";
import { PublishStatus } from "../publish-status/index.js";
import styles from "./index.module.scss";

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

function excerpt(value: string, fallback: string): string {
  const normalized = value.trim();
  return normalized || fallback;
}

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
