import fs from 'node:fs';
import path from 'node:path';
import yaml from 'js-yaml';
import type { LoadContext, Plugin } from '@docusaurus/types';

import type { PackageCoverage } from './types';

// The CI workflow lists the packages with a coverage job: the site reads it.
const workflow = '.github/workflows/main.yaml';

type Job = {
  with?: {
    working_directory?: string;
    package_name?: string;
  };
};

type Pubspec = { name: string; publish_to?: string };

function loadCoverage(repoRoot: string): PackageCoverage[] {
  const { jobs } = yaml.load(
    fs.readFileSync(path.join(repoRoot, workflow), 'utf8'),
  ) as { jobs: Record<string, Job> };

  return Object.values(jobs).flatMap(({ with: inputs }) => {
    if (
      inputs?.working_directory === undefined ||
      inputs.package_name === undefined
    ) {
      return [];
    }
    const packagePath = path.normalize(inputs.working_directory);
    const pubspec = yaml.load(
      fs.readFileSync(path.join(repoRoot, packagePath, 'pubspec.yaml'), 'utf8'),
    ) as Pubspec;
    if (pubspec.publish_to === 'none') {
      return [];
    }
    if (pubspec.name !== inputs.package_name) {
      throw new Error(
        `${workflow}: package_name "${inputs.package_name}" is not the pub ` +
          `name "${pubspec.name}" of ${packagePath}.`,
      );
    }
    return [{ name: pubspec.name, path: packagePath }];
  });
}

export default function coveragePlugin(
  context: LoadContext,
): Plugin<PackageCoverage[]> {
  const repoRoot = path.resolve(context.siteDir, '..');

  return {
    name: 'coverage',

    getPathsToWatch() {
      return [path.join(repoRoot, workflow)];
    },

    async loadContent() {
      return loadCoverage(repoRoot);
    },

    async contentLoaded({ content, actions }) {
      actions.setGlobalData({ packages: content });
    },
  };
}
