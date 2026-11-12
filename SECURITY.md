# Security Policy

MacBlueprint looks at your Mac's setup, so trust matters more than features.

## What MacBlueprint reads

| Reads | Never reads |
|---|---|
| App bundles' `Info.plist` in `/Applications` and `~/Applications` | `~/.ssh`, `~/.gnupg`, `~/Library/Keychains` |
| Homebrew's own package list (`brew info --json`, `brew tap`) | `~/.aws`, `~/.azure`, `~/.config/gcloud`, `~/.config/gh` |
| Editor extension manifests (`~/.vscode/extensions/extensions.json`, …) | `~/.kube`, `~/.docker`, `~/.netrc`, `~/.npmrc`, `~/.pypirc`, `~/.git-credentials` |
| `--version` output of developer tools | Any `.env*` file, anywhere |
| Whether shell framework folders *exist* (never their contents) | App Store purchase metadata (`iTunesMetadata.plist`) |
| Spotlight's App Store ID for App Store apps | The contents of your dotfiles (until v1.0, behind a secret scanner) |

The "never reads" list is enforced in [`Exclusions.swift`](Sources/BlueprintCore/Privacy/Exclusions.swift) and covered by tests.

## Network and installs

- **Network:** MacBlueprint makes exactly one kind of request, and only with `restore --match-casks`: it downloads Homebrew's public cask list from `https://formulae.brew.sh/api/cask.json`. Nothing about your Mac is sent; it's a plain download. A compact index is cached in `~/Library/Caches/MacBlueprint/`.
- **Installs:** `macblueprint` never installs anything. `restore` only writes `PLAN.md`, `Brewfile` and `restore.sh`. The script asks before it changes anything, supports `--dry-run`, and does not install Homebrew for you.

## Reporting a vulnerability

If you find a way MacBlueprint could read, store or leak sensitive data, **please don't open a public issue**. Report it privately through GitHub: **Security → Report a vulnerability** on this repository.

Please include steps to reproduce and the macOS version. You'll get a reply within a few days.
