/** A published package whose coverage the CI measures. */
export type PackageCoverage = {
  /** The pub name, which is also the Codecov flag. */
  name: string;
  /** The package folder, from the repository root. */
  path: string;
};
