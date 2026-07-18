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

const config: Config = {
  title: 'CRDT',
  tagline: 'Conflict-free Replicated Data Type in Dart 🎯',
  favicon: undefined,

  customFields: { examplesUrl, projectUrl },

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // `detect` keeps `.md` files (the copied package READMEs) on CommonMark so
  // their raw HTML (e.g. `<div>`, `<img>`) renders as on GitHub, while `.mdx`
  // stays MDX. `mermaid: true` enables ```mermaid code fences.
  markdown: {
    format: 'detect',
    mermaid: true,
  },

  themes: ['@docusaurus/theme-mermaid'],

  // Set the production url of your site here
  url: 'https://MattiaPispisa.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/crdt/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'Mattia Pispisa', // Usually your GitHub org/user name.
  projectName: 'crdt', // Usually your repo name.

  onBrokenLinks: 'throw',

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
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Social card (og:image). Lives in static/images, copied in by docs_bs.
    image: 'images/logo.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'CRDT in Dart',
      items: [
        {
          label: "Examples",
          position: "left",
          href: examplesUrl,
        },
        {
          to: '/docs/documentation',
          position: 'left',
          label: 'Documentation',
        },
        {
          to: '/docs/contributing',
          position: 'left',
          label: 'Contributing',
        },
        {
          to: '/docs/references',
          position: 'left',
          label: 'References',
        },
        {
          href: 'https://github.com/MattiaPispisa/crdt',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Contributing',
              to: '/docs/contributing',
            },
            {
              label: 'References',
              to: '/docs/references',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'Portfolio',
              href: 'https://mattiapispisa.it/#about',
            },
            {
              label: 'X',
              href: 'https://x.com/MattiaPispisa',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/MattiaPispisa/crdt',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} CRDT_LF, Inc.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
