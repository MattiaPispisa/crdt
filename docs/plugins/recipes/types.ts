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
};
