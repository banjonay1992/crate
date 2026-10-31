# Changelog

All notable changes to Crate are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-31

First version.

### Added

- CrateCore Swift package with no third-party dependencies:
  - Discogs API client for identity, database search, release details, marketplace stats, price suggestions, collection and wantlist, with User-Agent and token headers, a sliding-window rate limiter that reads the Discogs rate limit headers, and exponential backoff with jitter on 429 and server errors.
  - Barcode handling for EAN-13, EAN-8, UPC-A and UPC-E with check digit validation and a canonical form, plus normalisation for catalogue numbers and matrix / run-out strings.
  - Pressing matcher that ranks candidates by evidence and reports a unique match, an ambiguous set with the run-out strings that tell them apart, or no match.
  - Ownership index for owned, wanted, and owned or wanted in another pressing.
  - File-based offline cache for the collection, wantlist, release details and prices, with size caps, freshness windows and schema versioning.
  - Lookup service that falls back to the cache and a persistent offline lookup queue when there is no connection, and a sync service that can prefetch wantlist details for offline matching.
  - Dig log store with visits grouped by shop and day, spend per currency, search and CSV export.
  - Unit tests using invented fixture data and a scripted mock transport.
- iOS app for iOS 17 and later: barcode scanner, manual entry, result and pressing detail screens, wantlist, collection, dig log, settings and offline lookup review.
- Discogs token stored in the Keychain, with an optional git-ignored `Secrets.xcconfig` for Debug builds.
- Privacy manifest, camera usage description and accessibility labels.
- XcodeGen project spec and GitHub Actions CI for macOS and Linux tests and the iOS Simulator build.
