import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import CodeBlock from "@theme/CodeBlock";
import TabItem from "@theme/TabItem";
import Tabs from "@theme/Tabs";

import {
  blobUrl,
  type Recipe as RecipeData,
  treeUrl,
  useRecipe,
  useVariants,
  variantQuery,
} from "./data";
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

function sourceFolder(recipe: RecipeData): string {
  return recipe.files[0].path.split("/").slice(0, -1).join("/");
}

function SourceLink({ recipe }: { recipe: RecipeData }): ReactNode {
  return (
    <a
      className={styles.link}
      href={treeUrl(sourceFolder(recipe))}
      target="_blank"
      rel="noopener noreferrer"
    >
      Source ↗
    </a>
  );
}

/** Where a recipe runs, the test that runs it and the packages it needs. */
function RecipeMeta({
  recipe,
  source = false,
}: {
  recipe: RecipeData;
  /** Whether to link the source here: a variant has a folder of its own. */
  source?: boolean;
}): ReactNode {
  return (
    <>
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
        {source && <SourceLink recipe={recipe} />}
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
    </>
  );
}

/** The files of a recipe and its install command, one tab each. */
function RecipeFiles({ recipe }: { recipe: RecipeData }): ReactNode {
  return (
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
  );
}

function RecipeKeyPoints({ recipe }: { recipe: RecipeData }): ReactNode {
  if (recipe.keyPoints.length === 0) {
    return null;
  }
  return (
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
  );
}

/**
 * A complete setup: the install command and every file of the recipe, one tab
 * each, as they are compiled and tested in `crdt_lf_recipes`.
 *
 * A recipe with variants (one per storage adapter, say) shows them as tabs:
 * each variant has its own files, packages, test and key points.
 */
export default function Recipe({ id }: { id: string }): ReactNode {
  const recipe = useRecipe(id);
  const variants = useVariants(recipe);
  const hasVariants = variants.length > 1;

  return (
    <section className={styles.recipe}>
      <header className={styles.header}>
        <div className={styles.titleRow}>
          <span className={styles.icon} aria-hidden>
            🍳
          </span>
          <span className={styles.title}>{recipe.title}</span>
          {!hasVariants && <SourceLink recipe={recipe} />}
        </div>
        <p className={styles.description}>
          <InlineText text={recipe.description} />
        </p>
        {!hasVariants && <RecipeMeta recipe={recipe} />}
      </header>

      {hasVariants ? (
        <div className={styles.variants}>
          <Tabs queryString={variantQuery} defaultValue={recipe.id}>
            {variants.map((variant) => (
              <TabItem
                key={variant.id}
                value={variant.id}
                label={variant.variant ?? variant.id}
              >
                <div className={styles.variantMeta}>
                  <RecipeMeta recipe={variant} source />
                </div>
                <RecipeFiles recipe={variant} />
                <RecipeKeyPoints recipe={variant} />
              </TabItem>
            ))}
          </Tabs>
        </div>
      ) : (
        <>
          <RecipeFiles recipe={recipe} />
          <RecipeKeyPoints recipe={recipe} />
        </>
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
