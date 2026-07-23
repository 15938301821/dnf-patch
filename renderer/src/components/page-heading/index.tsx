/**
 * @fileoverview 提供路由页面共用的标题、说明和可选命令区域。
 *
 * 各页面通过 Props 提供静态文案与操作节点；组件只负责语义化布局，不读取状态或产生副作用。
 */
import type { ReactNode } from "react";
import styles from "./index.module.scss";

/** 页面标题组件的展示契约。 */
interface PageHeadingProps {
  title: string;
  description: string;
  action?: ReactNode;
}

/**
 * 渲染页面级标题和可选操作区。
 *
 * @param props 页面提供的标题、描述和命令节点；命令行为仍由父页面拥有。
 * @returns 语义化 header，不发请求或改写路由。
 */
export function PageHeading({
  title,
  description,
  action,
}: PageHeadingProps): React.JSX.Element {
  return (
    <header className={styles.heading}>
      <div>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action ? <div className={styles.action}>{action}</div> : null}
    </header>
  );
}
