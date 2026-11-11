const config = {
  '*.{js,ts}': 'eslint --fix',
  '*.mjs': ['oxfmt', 'eslint --fix'],
  '**/*.ts': () => 'tsc -p tsconfig.json --noEmit',
};

export default config;
