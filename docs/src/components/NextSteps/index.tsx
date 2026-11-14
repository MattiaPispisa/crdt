import type { ReactNode } from "react";
import Link from "@docusaurus/Link";

import styles from "./styles.module.css";

export type NextStep = {
  title: string;
  to: string;
  description?: string;
};

/** A row of cards that sends the reader to the next pages to read. */
export default function NextSteps({
  title = "Next steps",
  items,
}: {
  title?: string;
  items: NextStep[];
}): ReactNode {
  return (
    <nav className={styles.nextSteps} aria-label={title}>
      <p className={styles.heading}>{title}</p>
      <div className={styles.grid}>
        {items.map((item) => (
          <Link key={item.to} to={item.to} className={styles.card}>
            <span className={styles.cardTitle}>{item.title} →</span>
            {item.description && (
              <span className={styles.cardDescription}>
                {item.description}
              </span>
            )}
          </Link>
        ))}
      </div>
    </nav>
  );
}
