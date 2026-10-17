// Global (self-hosted admin) config for the Renovate workflow. Repo-level rules
// live in renovate.json. `binarySource: 'install'` lets Renovate's containerbase
// install Dart/Flutter on demand so it can resolve pubspec.lock.
module.exports = {
  platform: "github",
  onboarding: false,
  requireConfig: "optional",
  branchPrefix: "renovate/",
  repositories: ["aaronbamblett/tsumige"],
  binarySource: "install",
};
