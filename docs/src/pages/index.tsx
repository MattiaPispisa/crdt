import type { ReactNode } from "react";
import clsx from "clsx";
import Link from "@docusaurus/Link";
import { translate } from "@docusaurus/Translate";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";

import styles from "./index.module.css";

type CardItem = {
  title: string;
  description?: string;
  url: string;
};

function Cards() {
  const { siteConfig } = useDocusaurusContext();
  const examplesUrl = siteConfig.customFields?.examplesUrl as string;
  const greyhoundUrl = siteConfig.customFields?.greyhoundUrl as string;

  const cards: CardItem[] = [
    {
      title: translate({
        id: "homepage.cards.greyhound.title",
        message: "Greyhound Markdown",
        description: "Title of the Greyhound Markdown card on the homepage",
      }),
      description: translate({
        id: "homepage.cards.greyhound.description",
        message:
          "A real-time collaborative markdown editor. Open it on separate " +
          "devices, join the same room and edit together.",
        description:
          "Description of the Greyhound Markdown card on the homepage",
      }),
      url: greyhoundUrl,
    },
    {
      title: translate({
        id: "homepage.cards.documentation.title",
        message: "Documentation",
        description: "Title of the Documentation card on the homepage",
      }),
      description: translate({
        id: "homepage.cards.documentation.description",
        message:
          "Start here — an intro to CRDTs and the docs for every package.",
        description: "Description of the Documentation card on the homepage",
      }),
      url: "/docs/documentation",
    },
    {
      title: translate({
        id: "homepage.cards.examples.title",
        message: "Examples",
        description: "Title of the Examples card on the homepage",
      }),
      description: translate({
        id: "homepage.cards.examples.description",
        message: "Try the interactive Flutter demo built from crdt_lf.",
        description: "Description of the Examples card on the homepage",
      }),
      url: examplesUrl,
    },
  ];

  return (
    <section className={styles.cards}>
      {cards.map((card) => (
        <Link key={card.url} to={card.url} className={styles.card}>
          <Heading as="h3" className={styles.cardTitle}>
            {card.title}
          </Heading>
          {card.description && (
            <p className={styles.cardDescription}>{card.description}</p>
          )}
        </Link>
      ))}
    </section>
  );
}

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className={clsx("hero hero--primary", styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
      </div>
    </header>
  );
}

const logoUrl = require("@site/static/images/logo.png").default;

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();

  return (
    <Layout title={`Hello from ${siteConfig.title}`}>
      <HomepageHeader />
      <main className={styles.main}>
        <img
          src={logoUrl}
          className={styles.logo}
          role="img"
          alt={siteConfig.title}
        />
        <Link href={siteConfig.customFields!.projectUrl as string}>
          Currently working on ...
        </Link>
        <Cards />
      </main>
    </Layout>
  );
}
