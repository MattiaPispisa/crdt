/** One file of a recipe, as the site shows it. */
export type RecipeFile = {
  /** Relative to the repository root. */
  path: string;
  label: string;
  language: string;
  /** The whole file, without the license header and the region markers. */
  code: string;
  /** The code between `#docregion <name>` and `#enddocregion <name>`. */
  regions: Record<string, string>;
};

/** A recipe: a complete setup, compiled and tested in `crdt_lf_recipes`. */
export type Recipe = {
  id: string;
  title: string;
  description: string;
  platforms: string[];
  /** The pub.dev names of the dependencies, without the SDK ones. */
  packages: string[];
  /** The `pub add` command of the dependencies. */
  install: string;
  files: RecipeFile[];
  /** The test that runs the recipe, relative to the repository root. */
  test: string | null;
  keyPoints: string[];
  related: { title: string; to: string }[];
  /**
   * The label of this recipe on a page that shows several variants of one
   * setup (one per storage adapter, say), or `null` when it has none.
   */
  variant: string | null;
  /**
   * The id of the recipe whose page shows this one as a variant. Such a
   * recipe has no page and no gallery card of its own.
   */
  variantOf: string | null;
};
