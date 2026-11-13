import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import CodeBlock from "@theme/CodeBlock";

import { blobUrl, recipeFile, recipeHref, useRecipe } from "../Recipe/data";
import styles from "../Recipe/styles.module.css";

/**
 * One region (or the whole file) of a recipe, inside a page: a snippet that
 * CI compiles and runs.
 */
export default function RecipeSnippet({
  id,
  file,
  region,
  title,
}: {
  id: string;
  /** The label or the path of the file in the recipe manifest. */
  file: string;
  /** A `#docregion` name, or several joined by commas; the whole file when omitted. */
  region?: string;
  title?: string;
}): ReactNode {
  const recipe = useRecipe(id);
  const source = recipeFile(recipe, file);
  const code =
    region === undefined
      ? source.code
      : region
          .split(",")
          .map((name) => {
            const body = source.regions[name.trim()];
            if (body === undefined) {
              throw new Error(`Recipe "${id}", file "${file}": no region "${name}".`);
            }
            return body;
          })
          .join("\n\n");

  return (
    <div className={styles.snippet}>
      <CodeBlock language={source.language} title={title}>
        {code}
      </CodeBlock>
      <div className={styles.snippetFooter}>
        <Link to={recipeHref(recipe)}>
          From the recipe “{recipe.title}” →
        </Link>
        <a href={blobUrl(source.path)} target="_blank" rel="noopener noreferrer">
          {source.label} ↗
        </a>
      </div>
    </div>
  );
}
