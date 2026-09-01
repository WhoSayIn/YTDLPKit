## Summary

Describe the behavior and why the change belongs in YTDLPKit's metadata-only scope.

## Verification

- [ ] `swift build`
- [ ] `swift test --skip LiveIntegrationTests`
- [ ] `swift format lint --recursive --strict Package.swift Sources Tests Examples`
- [ ] Example app built when the public API changed
- [ ] Simulator and physical-device validation recorded when runtime packaging changed

## Safety and release impact

- [ ] No live YouTube dependency was added to ordinary CI
- [ ] No signed URLs, cookies, credentials, authorization data, or unsanitized Python output were committed or logged
- [ ] Third-party notices and provenance were updated for dependency/runtime changes
- [ ] Public API and semantic-versioning impact is documented
