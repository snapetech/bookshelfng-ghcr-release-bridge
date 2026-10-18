# BookshelfNG GHCR release bridge

This small repository republishes the exact multi-architecture ChaptarrNG compatibility image digests under the mutable legacy BookshelfNG GHCR tags. The `latest`, `main`, and `hardcover` aliases use the image with `HARDCOVER=true`; `softcover` uses the image with `HARDCOVER=false`. This preserves the source provider mode for bare numeric IDs during automatic database migration. The bridge performs no application build and does not change pinned or versioned tags.

The bridge accepts only a `repository_dispatch` event from the ChaptarrNG release workflow with a strict semantic version, source commit, and three `sha256:` digests for the standard, softcover, and Hardcover images. It refuses a release unless that exact version is the current latest stable ChaptarrNG release. A shared concurrency group prevents simultaneous updates to the moving aliases. The destination and alias-to-flavor mapping are fixed in the script. Each published alias is checked against its matching source digest; a mismatch fails the run.

## One-time GitHub setup

1. Keep this repository under the `snapetech` personal account so its `GITHUB_TOKEN` can be granted access to the user-owned `bookshelfng` container package.
2. In the `bookshelfng` package settings, add this repository under **Manage Actions access** with package write access. The bridge reads the public ChaptarrNG package without a separate credential.
3. Install the existing **SnapeTech Automation** GitHub App on the `snapetech` account, restricted to this repository, with repository contents write access. The ChaptarrNG organization release workflow uses a generated installation token to dispatch the release event.
4. Keep `CHAPTARRNG_MIGRATION_BRIDGE_ENABLED` unset or `false` until the migration, rollback, feature-parity, and per-channel gates pass. Turning it on enables the live legacy mutable tags.

The repository and App installation are durable configuration. GitHub App installation tokens and the workflow's `GITHUB_TOKEN` are minted for each run and expire automatically; no personal access token is stored.

## Local validation

Run `bash scripts/test-ghcr-release-bridge.sh`. The test replaces Buildx with a local mock and proves that the four fixed tags receive the matching provider-mode digest, digest mismatches fail, and malformed inputs are rejected.
