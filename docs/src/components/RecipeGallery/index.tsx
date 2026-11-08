import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import { useDocsSidebar } from "@docusaurus/plugin-content-docs/client";
import type { PropSidebarItem } from "@docusaurus/plugin-content-docs";

import { InlineText, Platforms } from "../Recipe";
import { type Recipe, useRecipes } from "../Recipe/data";
import styles from "../Recipe/styles.module.css";

// Every link of the sidebar, in its order.
function sidebarHrefs(items: PropSidebarItem[]): string[] {
  return items.flatMap((item) => {
    if (item.type === "category") {
      return [...(item.href ? [item.href] : []), ...sidebarHrefs(item.items)];
    }
    return item.type === "link" ? [item.href] : [];
  });
}

// The recipes in the order of the sidebar (simple first), so the order is
// written in one place. A recipe with no sidebar entry goes last.
function useOrderedRecipes(): Recipe[] {
  const recipes = useRecipes();
  const hrefs = sidebarHrefs(useDocsSidebar()?.items ?? []);
  const rank = (recipe: Recipe) => {
    const index = hrefs.findIndex((href) =>
      href.replace(/\/$/, "").endsWith(`/recipes/${recipe.id}`),
    );
    return index === -1 ? hrefs.length : index;
  };
  return [...recipes].sort((a, b) => rank(a) - rank(b));
}

/** A card for every recipe, each one linking to its page. */
export default function RecipeGallery(): ReactNode {
  return (
    <div className={styles.gallery}>
      {useOrderedRecipes().map((recipe) => (
        <Link
          key={recipe.id}
          to={`/docs/recipes/${recipe.id}`}
          className={styles.card}
        >
          <span className={styles.cardTitle}>🍳 {recipe.title}</span>
          <span className={styles.cardDescription}>
            <InlineText text={recipe.description} />
          </span>
          <Platforms platforms={recipe.platforms} />
          <span className={styles.cardPackages}>
            {recipe.packages.join(" · ")}
          </span>
        </Link>
      ))}
    </div>
  );
}
