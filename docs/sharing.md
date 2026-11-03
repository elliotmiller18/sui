# Preparing a public repository or app

The working tree contains source, required data and documentation. Build
products, solver outputs and editor files do not belong in commits. Run
`./scripts/test.sh` before preparing a release; it leaves no test artifacts.

Before public distribution:

- Choose a license for Sui's own code. The engine is AGPL-3.0; its license and
  source are retained. The root project currently has no license declaration.
- Resolve redistribution permissions for the downloaded preflop chart packs
  and confirm the status of lookup data. Provenance alone does not establish
  permission. See [third-party notices](../THIRD_PARTY_NOTICES.md).
- If publishing an app, distribute the corresponding source from the same
  revision and retain the bundled licenses and engine source archive.
- Build for the recipient's architecture and compatible macOS/OpenMP version.
  Current builds are not universal, Developer ID signed or notarized.

## Git history

The original commit includes a ~26 MiB sample strategy output and uncompressed
lookup tables. They are removed/replaced in the current tree, but remain in
existing Git history. No history rewrite or remote push is performed by the
cleanup. To publish without that baggage, export the reviewed working tree
into a new repository or deliberately rewrite history before the first public
push. A history rewrite affects existing clones and needs a separate decision.

Review `git status --short` before staging. Preserve the chart provenance,
compressed lookup tables, build scripts and vendor license files. Do not add
`build/`, `dist/`, `.env` files, private hand histories or solver results.
