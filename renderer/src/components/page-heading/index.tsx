import type { ReactNode } from "react";
import styles from "./index.module.scss";

interface PageHeadingProps {
  title: string;
  description: string;
  action?: ReactNode;
}

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
