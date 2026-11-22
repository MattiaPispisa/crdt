/** A published package and the coverage its CI job asks for. */
export type PackageCoverage = {
  /** The pub name, which is also the Codecov flag. */
  name: string;
  /** The package folder, from the repository root. */
  path: string;
  /** The percentage under which the CI job fails. */
  minCoverage: number;
};
