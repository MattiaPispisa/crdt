import type { ReactNode } from "react";
import clsx from "clsx";
import Link from "@docusaurus/Link";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";

import styles from "./index.module.css";

type CardItem = {
  title: string;
  description?: string;
  url: string;
};

const cards: CardItem[] = [
  {
    title: "Examples", // TODO: fill in
    url: "", // TODO: fill in
  },
];

function Cards() {
  return (
    <section className={styles.cards}>
      {cards.map((card) => (
        <Link key={card.url} to={card.url} className={styles.card}>
          <Heading as="h3" className={styles.cardTitle}>
            {card.title}
          </Heading>
          {card.description && <p className={styles.cardDescription}>{card.description}</p>}
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
        <img src={logoUrl} className={styles.logo} role="img" alt={siteConfig.title} />
        <Cards />
      </main>
    </Layout>
  );
}
