import fs from 'node:fs';
import path from 'node:path';
import yaml from 'js-yaml';
import type { LoadContext, Plugin } from '@docusaurus/types';

import { readRecipeSource } from './source';
import type { Recipe, RecipeFile } from './types';

// The recipes are compiled and tested in this package: the site shows the
// files as they are there, so a snippet on a page is code that CI runs.
const recipesPackage = 'packages/_internal/crdt_lf_recipes';

type Manifest = {
  id: string;
  title: string;
  description: string;
  platforms?: string[];
  dependencies?: string[];
  sdkDependencies?: string[];
  files: { path: string; label?: string }[];
  test?: string;
  keyPoints?: string[];
  related?: { title: string; to: string }[];
  variant?: string;
  variantOf?: string;
};

// The command that adds the dependencies, wrapped at 80 columns. A recipe
// that runs on the Dart VM uses `dart pub add`, which works in a Flutter app
// too.
function installCommand(manifest: Manifest): string {
  const tool = manifest.platforms?.includes('Dart VM') ? 'dart' : 'flutter';
  const words = [
    ...(manifest.dependencies ?? []),
    ...(manifest.sdkDependencies ?? []).map((name) => `"${name}@{sdk: flutter}"`),
  ];
  const lines: string[] = [];
  let line = `${tool} pub add`;
  for (const word of words) {
    if (line.length + word.length + 3 > 80) {
      lines.push(`${line} \\`);
      line = ' ';
    }
    line += ` ${word}`;
  }
  lines.push(line);
  return lines.join('\n');
}

function loadRecipe(repoRoot: string, manifestPath: string): Recipe {
  const manifest = yaml.load(fs.readFileSync(manifestPath, 'utf8')) as Manifest;
  const files: RecipeFile[] = manifest.files.map((file) => {
    const absolute = path.join(repoRoot, file.path);
    if (!fs.existsSync(absolute)) {
      throw new Error(`Recipe ${manifest.id}: ${file.path} does not exist.`);
    }
    const source = readRecipeSource(fs.readFileSync(absolute, 'utf8'));
    return {
      path: file.path,
      label: file.label ?? path.basename(file.path),
      language: path.extname(file.path).slice(1) || 'text',
      code: source.code,
      regions: source.regions,
    };
  });
  if (manifest.test && !fs.existsSync(path.join(repoRoot, manifest.test))) {
    throw new Error(`Recipe ${manifest.id}: ${manifest.test} does not exist.`);
  }
  return {
    id: manifest.id,
    title: manifest.title,
    description: manifest.description,
    platforms: manifest.platforms ?? [],
    // The SDK packages have no pub.dev page: the install command lists them.
    packages: manifest.dependencies ?? [],
    install: installCommand(manifest),
    files,
    test: manifest.test ?? null,
    keyPoints: manifest.keyPoints ?? [],
    related: manifest.related ?? [],
    variant: manifest.variant ?? null,
    variantOf: manifest.variantOf ?? null,
  };
}

// A variant is shown on the page of another recipe, as one of its tabs: both
// need a label, and the page must be a recipe with a page of its own.
function checkVariants(recipes: Recipe[]): void {
  for (const recipe of recipes) {
    if (recipe.variantOf === null) continue;
    const main = recipes.find((candidate) => candidate.id === recipe.variantOf);
    if (!main) {
      throw new Error(
        `Recipe ${recipe.id}: no recipe "${recipe.variantOf}" to be a variant of.`,
      );
    }
    if (main.variantOf !== null) {
      throw new Error(
        `Recipe ${recipe.id}: "${main.id}" is a variant itself.`,
      );
    }
    for (const labelled of [recipe, main]) {
      if (labelled.variant === null) {
        throw new Error(`Recipe ${labelled.id}: a variant needs a "variant" label.`);
      }
    }
  }
}

export default function recipesPlugin(context: LoadContext): Plugin<Recipe[]> {
  const repoRoot = path.resolve(context.siteDir, '..');
  const manifestsDir = path.join(repoRoot, recipesPackage, 'recipes');

  return {
    name: 'recipes',

    getPathsToWatch() {
      // The manifests, and every file they show: some live in other packages.
      const files = fs
        .readdirSync(manifestsDir)
        .filter((name) => name.endsWith('.yaml'))
        .flatMap((name) => {
          const manifest = yaml.load(
            fs.readFileSync(path.join(manifestsDir, name), 'utf8'),
          ) as Manifest;
          return manifest.files.map((file) => path.join(repoRoot, file.path));
        });
      return [path.join(manifestsDir, '*.yaml'), ...files];
    },

    async loadContent() {
      const recipes = fs
        .readdirSync(manifestsDir)
        .filter((name) => name.endsWith('.yaml'))
        .sort()
        .map((name) => loadRecipe(repoRoot, path.join(manifestsDir, name)));
      checkVariants(recipes);
      return recipes;
    },

    async contentLoaded({ content, actions }) {
      actions.setGlobalData({ recipes: content });
    },
  };
}
