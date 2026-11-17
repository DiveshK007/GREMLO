import js from "@eslint/js";
import tseslint from "typescript-eslint";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";

// Tuned to the code as it is: the rules below catch real bugs (unused code, empty handlers, loose any) without
// restyling a hand-formatted codebase. Formatting is Prettier's job, checked on changed files only (see CI).
export default tseslint.config(
  { ignores: ["**/node_modules/**", "**/.next/**", "apps/web/public/**", "apps/web/next-env.d.ts", "packages/brain/scripts/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
    plugins: { "react-hooks": reactHooks },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrors: "none" }],
      "@typescript-eslint/ban-ts-comment": ["error", { "ts-expect-error": "allow-with-description", minimumDescriptionLength: 10 }],
      "no-empty": ["error", { allowEmptyCatch: true }],
    },
  },
  { files: ["**/*.test.ts", "**/*.test.js"], rules: { "@typescript-eslint/no-explicit-any": "off" } }, // tests poke at internals on purpose
);
