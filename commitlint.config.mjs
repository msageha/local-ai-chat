/** @type {import('@commitlint/types').UserConfig} */
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // 日本語の件名が英語の固有名詞 (Renovate, GitHub 等) で始まると誤検知するため、大文字小文字は検査しない
    "subject-case": [0],
  },
};
