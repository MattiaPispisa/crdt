import type { ReactNode } from "react";

import styles from "./styles.module.css";

/** A large card that points to an article worth reading first. */
export default function FeaturedPost({
  eyebrow,
  title,
  href,
  source,
  description,
}: {
  eyebrow: string;
  title: string;
  href: string;
  source: string;
  description: string;
}): ReactNode {
  return (
    <a
      className={styles.post}
      href={href}
      target="_blank"
      rel="noopener noreferrer"
    >
      <span className={styles.eyebrow}>{eyebrow}</span>
      <span className={styles.title}>{title}</span>
      <span className={styles.description}>{description}</span>
      <span className={styles.cta}>Read it on {source} ↗</span>
    </a>
  );
}
