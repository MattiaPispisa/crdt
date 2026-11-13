import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import { useDocsSidebar } from "@docusaurus/plugin-content-docs/client";
import type { PropSidebarItem } from "@docusaurus/plugin-content-docs";

import { InlineText, Platforms } from "../Recipe";
import { type Recipe, useRecipes, useVariants } from "../Recipe/data";
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
  // A variant is a tab on the page of its recipe: it has no card.
  return recipes
    .filter((recipe) => recipe.variantOf === null)
    .sort((a, b) => rank(a) - rank(b));
}

/** The card of one recipe, with the variants its page shows. */
function RecipeCard({ recipe }: { recipe: Recipe }): ReactNode {
  const variants = useVariants(recipe);
  const packages = [...new Set(variants.flatMap((variant) => variant.packages))];
  return (
    <Link to={`/docs/recipes/${recipe.id}`} className={styles.card}>
      <span className={styles.cardTitle}>🍳 {recipe.title}</span>
      <span className={styles.cardDescription}>
        <InlineText text={recipe.description} />
      </span>
      <Platforms platforms={recipe.platforms} />
      {variants.length > 1 && (
        <span className={styles.cardVariants}>
          {variants.map((variant) => variant.variant).join(" · ")}
        </span>
      )}
      <span className={styles.cardPackages}>{packages.join(" · ")}</span>
    </Link>
  );
}

/** A card for every recipe, each one linking to its page. */
export default function RecipeGallery(): ReactNode {
  return (
    <div className={styles.gallery}>
      {useOrderedRecipes().map((recipe) => (
        <RecipeCard key={recipe.id} recipe={recipe} />
      ))}
    </div>
  );
}
