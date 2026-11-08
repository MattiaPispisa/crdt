import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

// Single source of truth for the Flutter web examples link. The app is built
// separately and served as a static folder at <baseUrl>/examples/.
// `pathname://` tells Docusaurus to treat it as a plain server path (skips SPA
// routing and the broken-link checker) while still prepending the baseUrl.
// Exposed via `customFields` so pages can read it with useDocusaurusContext.
const examplesUrl = 'pathname:///examples/';
const projectUrl = 'https://github.com/users/MattiaPispisa/projects/1';
// Greyhound Markdown: a standalone real-time collaborative editor app built on
// crdt_lf / crdt_lf_flutter, hosted separately (absolute external URL, so it is
// a plain `href` and is skipped by the broken-link checker).
const greyhoundUrl = 'https://mattiapispisa.it/crdt/greyhound_markdown/';
const githubUrl = 'https://github.com/MattiaPispisa/crdt';

// The old site had one page per package README, under this name.
const legacyPackagePages: Record<string, string> = {
  crdt_lf: '/docs/getting-started',
  crdt_lf_flutter: '/docs/connectors/flutter',
  crdt_lf_quill: '/docs/connectors/flutter/editors/quill',
  crdt_socket_sync: '/docs/connectors/sync',
  dart_frog: '/docs/connectors/sync/server-frameworks',
  serverpod: '/docs/connectors/sync/server-frameworks',
  crdt_lf_persistence: '/docs/connectors/persistence',
  crdt_lf_hive: '/docs/connectors/persistence/adapters',
  crdt_lf_sqlite: '/docs/connectors/persistence/adapters',
  crdt_lf_drift: '/docs/connectors/persistence/adapters',
  hlc: '/docs/deep-dive/time-hlc',
  crdt_lf_devtools_extension: '/docs/deep-dive/devtools',
};

const config: Config = {
  title: 'CRDT in Dart',
  tagline:
    'Local-first, collaborative apps in Dart and Flutter. Every peer edits ' +
    'offline, and every copy converges.',
  favicon: 'images/logo.png',

  customFields: { examplesUrl, projectUrl, greyhoundUrl },

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // `detect` keeps `.md` files (the guide copied from GitHub) on CommonMark so
  // their raw HTML renders as on GitHub, while `.mdx` stays MDX.
  // `mermaid: true` enables ```mermaid code fences.
  markdown: {
    format: 'detect',
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  themes: ['@docusaurus/theme-mermaid'],

  plugins: [
    // offline, client-side search
    'docusaurus-plugin-pagefind',
    [
      '@docusaurus/plugin-client-redirects',
      {
        // The package READMEs already published on pub.dev link to the old
        // pages, so every one of them lands on its new home.
        redirects: [
          { from: '/docs', to: '/docs/introduction' },
          { from: '/docs/documentation', to: '/docs/introduction' },
          ...Object.entries(legacyPackagePages).map(([name, to]) => ({
            from: `/docs/documentation/packages/${name}`,
            to,
          })),
        ],
      },
    ],
  ],

  // Set the production url of your site here.
  // The GitHub Pages custom domain, not the github.io one: that host only
  // 301s here, and a canonical (or a sitemap entry) on it would point every
  // crawler at a redirect on another domain.
  url: 'https://mattiapispisa.it',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/crdt/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'Mattia Pispisa', // Usually your GitHub org/user name.
  projectName: 'crdt', // Usually your repo name.

  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',

  deploymentBranch: 'gh-pages',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
        sitemap: {
          // Docusaurus only knows its own routes. The Flutter web apps are
          // static folders the Pages workflow copies into the built site
          // afterwards, so they reach the sitemap only by being added here.
          createSitemapItems: async ({ defaultCreateSitemapItems, ...rest }) => [
            ...(await defaultCreateSitemapItems(rest)),
            { url: greyhoundUrl, changefreq: 'weekly', priority: 0.8 },
          ],
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Mermaid's defaults draw a diagram with the body font size and wide
    // gaps, so even a short flow fills the page.
    mermaid: {
      theme: { light: 'neutral', dark: 'dark' },
      options: {
        themeVariables: { fontSize: '13px' },
        flowchart: { nodeSpacing: 28, rankSpacing: 32, padding: 10 },
        sequence: {
          actorMargin: 40,
          boxMargin: 6,
          messageMargin: 28,
          noteMargin: 6,
          messageFontSize: 13,
          noteFontSize: 12,
          actorFontSize: 13,
        },
      },
    },
    // Social card (og:image). Lives in static/images, copied in by docs_bs.
    image: 'images/logo.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'CRDT in Dart',
      logo: {
        alt: 'CRDT in Dart',
        src: 'images/logo.png',
      },
      hideOnScroll: true,
      items: [
        {
          to: '/docs/introduction',
          position: 'left',
          label: 'Docs',
        },
        {
          to: '/docs/document',
          position: 'left',
          label: 'Document',
        },
        {
          to: '/docs/use-cases',
          position: 'left',
          label: 'Use cases',
        },
        {
          to: '/docs/connectors',
          position: 'left',
          label: 'Connectors',
        },
        {
          to: '/docs/deep-dive',
          position: 'left',
          label: 'Deep dive',
        },
        {
          to: '/docs/benchmarks',
          position: 'left',
          label: 'Benchmarks',
        },
        {
          label: 'Live demos',
          position: 'right',
          items: [
            { label: 'Greyhound Markdown', href: greyhoundUrl },
            { label: 'Flutter examples', href: examplesUrl },
          ],
        },
        {
          href: githubUrl,
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Learn',
          items: [
            { label: 'Introduction', to: '/docs/introduction' },
            { label: 'Getting started', to: '/docs/getting-started' },
            { label: 'The document', to: '/docs/document' },
            { label: 'Use cases', to: '/docs/use-cases' },
            { label: 'Deep dive', to: '/docs/deep-dive' },
            { label: 'Benchmarks', to: '/docs/benchmarks' },
          ],
        },
        {
          title: 'Connect',
          items: [
            { label: 'Persistence', to: '/docs/connectors/persistence' },
            { label: 'Flutter', to: '/docs/connectors/flutter' },
            { label: 'Sync', to: '/docs/connectors/sync' },
            { label: 'Migrations', to: '/docs/migrations' },
          ],
        },
        {
          title: 'Project',
          items: [
            { label: 'Packages', to: '/docs/packages' },
            { label: 'Contributing', to: '/docs/contributing' },
            { label: 'References', to: '/docs/references' },
            { label: 'Roadmap', href: projectUrl },
          ],
        },
        {
          title: 'Community',
          items: [
            { label: 'GitHub', href: githubUrl },
            { label: 'Portfolio', href: 'https://mattiapispisa.it/#about' },
            { label: 'X', href: 'https://x.com/MattiaPispisa' },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Mattia Pispisa. Released under the MIT License.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
