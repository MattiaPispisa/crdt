import { usePluginData } from "@docusaurus/useGlobalData";

import type { Recipe, RecipeFile } from "../../../plugins/recipes/types";

export type { Recipe, RecipeFile };

const githubUrl = "https://github.com/MattiaPispisa/crdt";

/** A file of the repository, on GitHub. */
export function blobUrl(path: string): string {
  return `${githubUrl}/blob/main/${path}`;
}

/** A folder of the repository, on GitHub. */
export function treeUrl(path: string): string {
  return `${githubUrl}/tree/main/${path}`;
}

/** Every recipe, in the order of their manifests. */
export function useRecipes(): Recipe[] {
  const { recipes } = usePluginData("recipes") as { recipes: Recipe[] };
  return recipes;
}

/** The recipe [id]; throws at build time when there is none. */
export function useRecipe(id: string): Recipe {
  const recipe = useRecipes().find((candidate) => candidate.id === id);
  if (!recipe) {
    throw new Error(`No recipe "${id}" in crdt_lf_recipes/recipes.`);
  }
  return recipe;
}

/** The query parameter that selects a variant on a recipe page. */
export const variantQuery = "variant";

/**
 * What the page of [recipe] shows as tabs: the recipe, then its variants. A
 * recipe with no variant gives only itself.
 */
export function useVariants(recipe: Recipe): Recipe[] {
  const variants = useRecipes().filter(
    (candidate) => candidate.variantOf === recipe.id,
  );
  return [recipe, ...variants];
}

/** The page of [recipe]. A variant opens its tab on the page that shows it. */
export function recipeHref(recipe: Recipe): string {
  return recipe.variantOf === null
    ? `/docs/recipes/${recipe.id}`
    : `/docs/recipes/${recipe.variantOf}?${variantQuery}=${recipe.id}`;
}

/** The file of [recipe] whose label or path is [file]. */
export function recipeFile(recipe: Recipe, file: string): RecipeFile {
  const found = recipe.files.find(
    (candidate) => candidate.label === file || candidate.path === file,
  );
  if (!found) {
    throw new Error(`Recipe "${recipe.id}" has no file "${file}".`);
  }
  return found;
}
