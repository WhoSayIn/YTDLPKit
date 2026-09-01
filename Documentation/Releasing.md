# Release process

YTDLPKit uses semantic versioning. Public API or behavior compatibility drives
the Swift package version; runtime revisions are recorded independently in the
release manifest and notices.

Creating a tag or release is a maintainer action. Automation validates a release
candidate but must not publish a repository, runtime artifact, tag, or GitHub
release without explicit approval.

## Version policy

- Patch: compatible bug fixes, redaction fixes, and compatible pinned runtime
  updates.
- Minor: backward-compatible API additions or meaningful new extractor output.
- Major: source-breaking API, platform, behavior, or runtime contract changes.

Pre-1.0 releases may make breaking changes in a minor version, but release notes
must call them out.

## Prepare the runtime artifact

1. Pin the CPython, yt-dlp, challenge-provider, build-tool, and binary
   dependency revisions.
2. Build from the documented clean environment for iOS device and Simulator.
3. Verify supported slices, minimum deployment target, module stability, and
   that consumers need no custom build phase.
4. Sign every final framework slice with the maintainer's stable distribution
   identity, then generate SHA-256 values, the SBOM, provenance, and complete
   third-party license bundle. Ad-hoc signatures are development validation
   only and are rejected by the release validator.
5. Run `.github/scripts/validate-vendored-runtime.sh` against a clean rebuild so
   the expanded binaries and resources match what SwiftPM consumers receive.
6. Run fixture and opt-in live tests, then validate extraction on a physical
   iPhone while disconnected from the development Mac.
7. Generate an Xcode privacy report from an archived example consumer and
   review required-reason API findings, including the documented CPython
   `statfs`/`fstatfs` risk.
8. Obtain explicit approval before uploading the artifact.

## Prepare the package release

1. Replace the repository URL placeholder with the approved public location and
   verify the vendored runtime manifest against a clean rebuild.
2. Remove all `TO BE FINALIZED` markers from `THIRD_PARTY_NOTICES.md` and include
   exact license texts in the release artifact.
3. Update the changelog/release notes, compatibility matrix, and pinned-version
   manifest.
4. Run:

   ```sh
   swift build
   swift test
   swift format lint --recursive --strict Sources Tests Examples
   .github/scripts/validate-release.sh X.Y.Z
   ```

5. Build DocC and the example app for an iOS Simulator.
6. Run the separately gated live workflow. Live network results are diagnostic;
   a transient upstream failure is investigated rather than hidden in normal CI.
7. Complete the physical-device acceptance checklist relevant to the release.

## Tag and publish

Only after explicit approval:

1. Merge the prepared, fully validated commit to the default branch.
2. Create an annotated `vX.Y.Z` tag that points to that commit.
3. Push the tag and confirm the release-validation workflow passes from the tag.
4. Create release notes describing API changes, runtime pins, security fixes,
   checksums, known limitations, and App Store considerations.
5. Publish the GitHub release without modifying its immutable runtime assets.
6. Verify a clean example consumer resolves the package by URL and imports only
   `YTDLPKit`.

If validation fails after tagging, do not replace artifacts behind an existing
URL. Correct the issue and publish a new semantic version.
