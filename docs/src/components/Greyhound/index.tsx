import type { ReactNode } from "react";
import useBaseUrl from "@docusaurus/useBaseUrl";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";

import styles from "./styles.module.css";

const sourceRoot =
  "https://github.com/MattiaPispisa/crdt/blob/main/apps/greyhound_markdown/";

/**
 * A box that shows how Greyhound Markdown uses the feature of the page: a
 * short text or snippet, a link to the live app and one to the source.
 *
 * `source` is a path under `apps/greyhound_markdown/`.
 */
export default function Greyhound({
  title = "In Greyhound Markdown",
  source,
  children,
}: {
  title?: string;
  source?: string;
  children: ReactNode;
}): ReactNode {
  const { siteConfig } = useDocusaurusContext();
  const greyhoundUrl = siteConfig.customFields?.greyhoundUrl as string;
  const logo = useBaseUrl("/images/greyhound_markdown_logo.png");

  return (
    <aside className={styles.greyhound}>
      <header className={styles.header}>
        <img className={styles.logo} src={logo} alt="" width={36} height={36} />
        <span className={styles.title}>{title}</span>
        <span className={styles.links}>
          <a href={greyhoundUrl} target="_blank" rel="noopener noreferrer">
            Try it live ↗
          </a>
          {source && (
            <a
              href={`${sourceRoot}${source}`}
              target="_blank"
              rel="noopener noreferrer"
            >
              Source ↗
            </a>
          )}
        </span>
      </header>
      <div className={styles.body}>{children}</div>
    </aside>
  );
}
