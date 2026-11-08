import type { ReactNode } from "react";
import clsx from "clsx";
import Link from "@docusaurus/Link";
import useBaseUrl from "@docusaurus/useBaseUrl";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";
import CodeBlock from "@theme/CodeBlock";

import styles from "./index.module.css";

type Card = {
  icon: string;
  title: string;
  description: string;
  to: string;
};

const features: Omit<Card, "to">[] = [
  {
    icon: "📴",
    title: "Offline first",
    description:
      "Every edit is applied locally at once. It reaches the other peers when a connection exists.",
  },
  {
    icon: "🔀",
    title: "No conflicts to solve",
    description:
      "Concurrent edits merge on their own, and every peer converges on the same state.",
  },
  {
    icon: "✍️",
    title: "Text that stays readable",
    description:
      "Fugue keeps the text of two people apart, and Peritext merges their formats.",
  },
  {
    icon: "↩️",
    title: "Undo your own edits",
    description:
      "An undo takes back what you did, and leaves everyone else's work alone.",
  },
  {
    icon: "🧩",
    title: "Plugs into your stack",
    description:
      "Hive, SQLite or Drift on the device. Dart Frog, Serverpod or a relay on the server.",
  },
  {
    icon: "🎯",
    title: "Pure Dart",
    description:
      "One engine on the VM, in Flutter on every platform, and on the web.",
  },
];

const useCases: Card[] = [
  {
    icon: "📝",
    title: "Collaborative text",
    description: "Notes and documents that people type into together.",
    to: "/docs/use-cases/collaborative-text",
  },
  {
    icon: "🅱️",
    title: "Rich text",
    description: "Bold, links, headings, images — up to a full Quill editor.",
    to: "/docs/use-cases/rich-text",
  },
  {
    icon: "📋",
    title: "Lists",
    description: "Ordered lists, and lists you reorder by drag and drop.",
    to: "/docs/use-cases/lists",
  },
  {
    icon: "🏷️",
    title: "Maps, sets and values",
    description: "Keys, tags and flags, with add-wins semantics.",
    to: "/docs/use-cases/maps-sets-values",
  },
  {
    icon: "🌳",
    title: "Nested data",
    description: "Trees of handlers: documents, boards, canvases.",
    to: "/docs/use-cases/containers",
  },
  {
    icon: "📦",
    title: "Aggregates",
    description: "Domain objects built from events.",
    to: "/docs/use-cases/aggregates",
  },
];

const connectors: Card[] = [
  {
    icon: "💾",
    title: "Persistence",
    description: "Hive · SQLite · Drift",
    to: "/docs/connectors/persistence",
  },
  {
    icon: "📱",
    title: "Flutter",
    description: "Widgets · text fields · Quill",
    to: "/docs/connectors/flutter",
  },
  {
    icon: "🔌",
    title: "Sync",
    description: "Dart Frog · Serverpod · relay",
    to: "/docs/connectors/sync",
  },
];

const snippet = `final alice = CRDTDocument();
final note = CRDTFugueTextHandler(alice, 'note');
note.insert(0, 'Hello world');

// Bob, on another device, offline until now.
final bob = CRDTDocument();
bob.importChanges(alice.exportChanges());

print(CRDTFugueTextHandler(bob, 'note').value);
// Hello world`;

function Hero() {
  const { siteConfig } = useDocusaurusContext();
  const greyhoundUrl = siteConfig.customFields?.greyhoundUrl as string;
  return (
    <header className={styles.hero}>
      <div className={clsx("container", styles.heroInner)}>
        <div className={styles.heroText}>
          <p className={styles.eyebrow}>Conflict-free Replicated Data Types</p>
          <Heading as="h1" className={styles.heroTitle}>
            Collaborative, local-first apps in <span>Dart</span> and{" "}
            <span>Flutter</span>
          </Heading>
          <p className={styles.heroSubtitle}>
            Every user edits their own copy, even offline. When the copies meet,
            they merge on their own, and everyone sees the same result.
          </p>
          <div className={styles.heroButtons}>
            <Link
              className="button button--primary button--lg"
              to="/docs/getting-started"
            >
              Get started
            </Link>
            <Link
              className="button button--secondary button--outline button--lg"
              href={greyhoundUrl}
            >
              ▶ Live demo
            </Link>
          </div>
          <CodeBlock language="sh" className={styles.install}>
            dart pub add crdt_lf
          </CodeBlock>
        </div>
        <div className={styles.heroCode}>
          <CodeBlock language="dart" title="main.dart">
            {snippet}
          </CodeBlock>
        </div>
      </div>
    </header>
  );
}

function CardGrid({ cards, columns }: { cards: Card[]; columns: number }) {
  return (
    <div
      className={styles.grid}
      style={{ ["--columns" as string]: columns }}
    >
      {cards.map((card) => (
        <Link key={card.to} to={card.to} className={styles.card}>
          <span className={styles.cardIcon} aria-hidden>
            {card.icon}
          </span>
          <Heading as="h3" className={styles.cardTitle}>
            {card.title}
          </Heading>
          <p className={styles.cardDescription}>{card.description}</p>
        </Link>
      ))}
    </div>
  );
}

function Features() {
  return (
    <section className={styles.section}>
      <div className="container">
        <div className={styles.features}>
          {features.map((feature) => (
            <div key={feature.title} className={styles.feature}>
              <span className={styles.cardIcon} aria-hidden>
                {feature.icon}
              </span>
              <Heading as="h3" className={styles.cardTitle}>
                {feature.title}
              </Heading>
              <p className={styles.cardDescription}>{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Demo() {
  const { siteConfig } = useDocusaurusContext();
  const greyhoundUrl = siteConfig.customFields?.greyhoundUrl as string;
  const examplesUrl = siteConfig.customFields?.examplesUrl as string;
  const screenshot = useBaseUrl("/images/greyhound_home_screen.png");
  return (
    <section className={clsx(styles.section, styles.sectionAlt)}>
      <div className={clsx("container", styles.demo)}>
        <div className={styles.demoText}>
          <Heading as="h2">See it working</Heading>
          <p>
            <strong>Greyhound Markdown</strong> is a real-time collaborative
            markdown editor built on these packages. Open it on two devices,
            join the same room and type together: no install needed.
          </p>
          <div className={styles.heroButtons}>
            <Link className="button button--primary" href={greyhoundUrl}>
              Open Greyhound Markdown
            </Link>
            <Link className="button button--secondary" href={examplesUrl}>
              Flutter examples
            </Link>
          </div>
        </div>
        <img
          className={styles.demoImage}
          src={screenshot}
          alt="Greyhound Markdown home screen"
          loading="lazy"
        />
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout title="Local-first CRDTs for Dart and Flutter" description={siteConfig.tagline}>
      <Hero />
      <main>
        <Features />
        <section className={styles.section}>
          <div className="container">
            <Heading as="h2" className={styles.sectionTitle}>
              What do your users edit?
            </Heading>
            <p className={styles.sectionSubtitle}>
              Pick the handler that matches the data. Each one has its own
              merge rules.
            </p>
            <CardGrid cards={useCases} columns={3} />
          </div>
        </section>
        <Demo />
        <section className={styles.section}>
          <div className="container">
            <Heading as="h2" className={styles.sectionTitle}>
              Connect it
            </Heading>
            <p className={styles.sectionSubtitle}>
              Keep it on the device, put it on screen, send it to the other
              peers.
            </p>
            <CardGrid cards={connectors} columns={3} />
            <p className={styles.more}>
              <Link to="/docs/packages">All packages →</Link>
              <Link href={siteConfig.customFields?.projectUrl as string}>
                Roadmap →
              </Link>
            </p>
          </div>
        </section>
      </main>
    </Layout>
  );
}
