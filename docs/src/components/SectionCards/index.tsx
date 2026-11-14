import type { ReactNode } from "react";
import { useLocation } from "@docusaurus/router";
import { useCurrentSidebarCategory } from "@docusaurus/plugin-content-docs/client";
import DocCardList from "@theme/DocCardList";

const withoutSlash = (path: string) => path.replace(/\/$/, "");

/**
 * A card for every page of the section this page opens, in the order of the
 * sidebar, each with the `description` of its front matter. A section overview
 * uses it instead of a list written by hand.
 */
export default function SectionCards(): ReactNode {
  const { pathname } = useLocation();
  // The overview is also the first entry of its own section: leave it out.
  const items = useCurrentSidebarCategory().items.filter(
    (item) =>
      item.type !== "link" ||
      withoutSlash(item.href) !== withoutSlash(pathname),
  );
  return <DocCardList items={items} />;
}
