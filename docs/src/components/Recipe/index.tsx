import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import CodeBlock from "@theme/CodeBlock";
import TabItem from "@theme/TabItem";
import Tabs from "@theme/Tabs";

import { blobUrl, treeUrl, useRecipe } from "./data";
import styles from "./styles.module.css";

/** Renders the `inline code` of a manifest sentence. */
export function InlineText({ text }: { text: string }): ReactNode {
  return text
    .split(/(`[^`]+`)/)
    .map((part, index) =>
      part.startsWith("`") && part.endsWith("`") ? (
        <code key={index}>{part.slice(1, -1)}</code>
      ) : (
        part
      ),
    );
}

/** The chips of the platforms a recipe runs on. */
export function Platforms({ platforms }: { platforms: string[] }): ReactNode {
  return (
    <span className={styles.chips}>
      {platforms.map((platform) => (
        <span key={platform} className={styles.chip}>
          {platform}
        </span>
      ))}
    </span>
  );
}

/**
 * A complete setup: the install command and every file of the recipe, one tab each,
 * as they are compiled and tested in `crdt_lf_recipes`.
 */
export default function Recipe({ id }: { id: string }): ReactNode {
  const recipe = useRecipe(id);
  const folder = recipe.files[0].path.split("/").slice(0, -1).join("/");

  return (
    <section className={styles.recipe}>
      <header className={styles.header}>
        <div className={styles.titleRow}>
          <span className={styles.icon} aria-hidden>
            🍳
          </span>
          <span className={styles.title}>{recipe.title}</span>
          <a
            className={styles.link}
            href={treeUrl(folder)}
            target="_blank"
            rel="noopener noreferrer"
          >
            Source ↗
          </a>
        </div>
        <p className={styles.description}>
          <InlineText text={recipe.description} />
        </p>
        <div className={styles.meta}>
          <Platforms platforms={recipe.platforms} />
          {recipe.test && (
            <a
              className={styles.tested}
              href={blobUrl(recipe.test)}
              target="_blank"
              rel="noopener noreferrer"
              title="Every file of this recipe is compiled and run by a test in CI"
            >
              ✓ tested in CI
            </a>
          )}
        </div>
        <div className={styles.packages}>
          {recipe.packages.map((name) => (
            <a
              key={name}
              href={`https://pub.dev/packages/${name}`}
              target="_blank"
              rel="noopener noreferrer"
            >
              {name}
            </a>
          ))}
        </div>
      </header>

      <div className={styles.files}>
        <Tabs defaultValue={recipe.files[0].label}>
          {recipe.files.map((file) => (
            <TabItem key={file.path} value={file.label} label={file.label}>
              <CodeBlock language={file.language} showLineNumbers>
                {file.code}
              </CodeBlock>
            </TabItem>
          ))}
          <TabItem value="install" label="Install">
            <CodeBlock language="sh">{recipe.install}</CodeBlock>
          </TabItem>
        </Tabs>
      </div>

      {recipe.keyPoints.length > 0 && (
        <div className={styles.keyPoints}>
          <p className={styles.keyPointsTitle}>Key points</p>
          <ul>
            {recipe.keyPoints.map((point) => (
              <li key={point}>
                <InlineText text={point} />
              </li>
            ))}
          </ul>
        </div>
      )}

      {recipe.related.length > 0 && (
        <footer className={styles.related}>
          <span>Read more:</span>
          {recipe.related.map((item) => (
            <Link key={item.to} to={item.to}>
              {item.title} →
            </Link>
          ))}
        </footer>
      )}
    </section>
  );
}
