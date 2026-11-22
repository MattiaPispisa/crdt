import type { ReactNode } from "react";
import { usePluginData } from "@docusaurus/useGlobalData";

import type { PackageCoverage } from "../../../plugins/package-coverage/types";
import styles from "./styles.module.css";

const repository = "MattiaPispisa/crdt";

function usePackages(only?: string[]): PackageCoverage[] {
  const { packages } = usePluginData("coverage") as {
    packages: PackageCoverage[];
  };
  if (only === undefined) {
    return packages;
  }
  return only.map((name) => {
    const found = packages.find((candidate) => candidate.name === name);
    if (!found) {
      throw new Error(`No published package "${name}" in the CI workflow.`);
    }
    return found;
  });
}

/**
 * The live Codecov badge of [pkg], linking to its report. A [named] badge
 * shows the package name in place of "coverage".
 */
function Badge({
  pkg,
  named = false,
}: {
  pkg: PackageCoverage;
  named?: boolean;
}): ReactNode {
  const label = named ? `&label=${pkg.name}` : "";
  return (
    <a
      href={`https://app.codecov.io/gh/${repository}/tree/main/${pkg.path}`}
      target="_blank"
      rel="noopener noreferrer"
    >
      <img
        className={styles.badge}
        src={`https://img.shields.io/codecov/c/github/${repository}/main?flag=${pkg.name}&logo=codecov${label}`}
        alt={`${pkg.name} coverage on Codecov`}
        loading="lazy"
      />
    </a>
  );
}

/** One row per published package: its live coverage and its CI minimum. */
export default function CoverageTable(): ReactNode {
  const packages = usePackages();
  return (
    <table>
      <thead>
        <tr>
          <th>Package</th>
          <th>Coverage on <code>main</code></th>
          <th>CI fails under</th>
        </tr>
      </thead>
      <tbody>
        {packages.map((pkg) => (
          <tr key={pkg.name}>
            <td>
              <a href={`https://pub.dev/packages/${pkg.name}`}>
                <code>{pkg.name}</code>
              </a>
            </td>
            <td>
              <Badge pkg={pkg} />
            </td>
            <td>{pkg.minCoverage}%</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** The live coverage badges of the packages named in [only], in a row. */
export function CoverageBadges({ only }: { only: string[] }): ReactNode {
  return (
    <div className={styles.badges}>
      {usePackages(only).map((pkg) => (
        <Badge key={pkg.name} pkg={pkg} named />
      ))}
    </div>
  );
}
