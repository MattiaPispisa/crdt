import type { ReactNode } from "react";
import useBaseUrl from "@docusaurus/useBaseUrl";

import styles from "./styles.module.css";

/** A demo image or GIF from `static/`, centered, with an optional caption. */
export default function Demo({
  src,
  alt,
  caption,
  width = 500,
}: {
  src: string;
  alt: string;
  caption?: ReactNode;
  width?: number;
}): ReactNode {
  return (
    <figure className={styles.demo}>
      <img src={useBaseUrl(src)} alt={alt} width={width} loading="lazy" />
      {caption && <figcaption>{caption}</figcaption>}
    </figure>
  );
}
