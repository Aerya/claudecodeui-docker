import fs from 'node:fs';

const configPath = 'upstream/src/i18n/config.js';
const languagesPath = 'upstream/src/i18n/languages.js';
const frLocaleDir = 'upstream/src/i18n/locales/fr';

const requiredNamespaces = [
  'common',
  'settings',
  'auth',
  'sidebar',
  'chat',
  'codeEditor',
  'tasks',
];

for (const namespace of requiredNamespaces) {
  const file = `${frLocaleDir}/${namespace}.json`;
  if (!fs.existsSync(file)) {
    throw new Error(`Missing French locale file: ${file}`);
  }
  JSON.parse(fs.readFileSync(file, 'utf8'));
}

let config = fs.readFileSync(configPath, 'utf8');

if (!config.includes("./locales/fr/common.json")) {
  const frImports = `
import frCommon from './locales/fr/common.json';
import frSettings from './locales/fr/settings.json';
import frAuth from './locales/fr/auth.json';
import frSidebar from './locales/fr/sidebar.json';
import frChat from './locales/fr/chat.json';
import frCodeEditor from './locales/fr/codeEditor.json';
// eslint-disable-next-line import-x/order
import frTasks from './locales/fr/tasks.json';
`;

  const languagesImport = "import { languages } from './languages.js';";
  if (!config.includes(languagesImport)) {
    throw new Error(`Unable to find languages import in ${configPath}`);
  }

  config = config.replace(languagesImport, `${frImports}\n${languagesImport}`);
}

if (!config.includes('frCommon')) {
  throw new Error('French imports were not inserted correctly.');
}

if (!/resources\s*:\s*\{\s*fr\s*:/.test(config)) {
  const frResources = `resources: {
    fr: {
      common: frCommon,
      settings: frSettings,
      auth: frAuth,
      sidebar: frSidebar,
      chat: frChat,
      codeEditor: frCodeEditor,
      tasks: frTasks,
    },`;

  config = config.replace(/resources\s*:\s*\{/, frResources);
}

fs.writeFileSync(configPath, config);

let languages = fs.readFileSync(languagesPath, 'utf8');

// Normalize the language list. This also protects the build if upstream's compact file
// temporarily contains a malformed language entry.
languages = languages.replace(
  /export const languages = \[[\s\S]*?\];/,
  `export const languages = [
  {
    value: 'en',
    label: 'English',
    nativeName: 'English',
  },
  {
    value: 'ko',
    label: 'Korean',
    nativeName: '한국어',
  },
  {
    value: 'zh-CN',
    label: 'Simplified Chinese',
    nativeName: '简体中文',
  },
  {
    value: 'ja',
    label: 'Japanese',
    nativeName: '日本語',
  },
  {
    value: 'ru',
    label: 'Russian',
    nativeName: 'Русский',
  },
  {
    value: 'de',
    label: 'German',
    nativeName: 'Deutsch',
  },
  {
    value: 'tr',
    label: 'Turkish',
    nativeName: 'Türkçe',
  },
  {
    value: 'it',
    label: 'Italian',
    nativeName: 'Italiano',
  },
  {
    value: 'fr',
    label: 'French',
    nativeName: 'Français',
  },
];`
);

if (!languages.includes("value: 'fr'")) {
  throw new Error(`Unable to add French language to ${languagesPath}`);
}

fs.writeFileSync(languagesPath, languages);

console.log('French locale overlay applied successfully.');
