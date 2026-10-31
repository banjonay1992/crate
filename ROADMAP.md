# Roadmap

Estimates are rough working hours for one developer. The total is about 64 hours.

Each item has a GitHub issue with a description and acceptance criteria, filed under the [v0.2](https://github.com/banjonay1992/crate/milestone/1), [v0.3](https://github.com/banjonay1992/crate/milestone/2) and [Later](https://github.com/banjonay1992/crate/milestone/3) milestones. Progress is tracked there; this file is the overview.

## Next (v0.2)

These make the first version trustworthy in a real shop and get it to testers.

1. **Field test on a device (4 h).** ([#1](https://github.com/banjonay1992/crate/issues/1)) Run the scanner against 50 real sleeves in varied light, including shrink-wrapped and glossy ones. Record misreads, how long a lookup takes on 3G and with no signal, and which UPC-E codes come through from AVFoundation as 6, 7 or 8 digits. Fix what turns up.
2. **Check every endpoint against the live API (3 h).** ([#2](https://github.com/banjonay1992/crate/issues/2)) With a throwaway Discogs account, capture real responses for search, release, marketplace stats, price suggestions, collection and wants. Keep their shape as new fixtures, with every value replaced by invented ones, and add tests for any field shape the invented fixtures got wrong, especially the error body for price suggestions without seller settings.
3. **App-level tests (5 h).** ([#3](https://github.com/banjonay1992/crate/issues/3)) Add an app test target. Unit test `AppModel` with an in-memory store and a mock `DiscogsAPI` (connect, disconnect clearing the cache, sync error handling, queue draining when connectivity returns). Add one UI test that types a catalogue number in manual entry and reaches the pressing chooser, and run both in CI on a named simulator.
4. **Rate limit visibility (2 h).** ([#4](https://github.com/banjonay1992/crate/issues/4)) Surface a short "Discogs asked Crate to slow down" banner when the limiter is pausing for more than a few seconds, so a long sync does not look frozen. Add a test for the pause reporting.
5. **Scan confirmation step (2 h).** ([#5](https://github.com/banjonay1992/crate/issues/5)) Before running a lookup, show the decoded digits for half a second with an undo, so an accidental scan of the wrong sleeve in a stack does not cost a request.
6. **TestFlight beta (4 h).** ([#6](https://github.com/banjonay1992/crate/issues/6)) Register the application with Discogs, archive a signed Release build, fill in the App Store Connect privacy answers to match the privacy manifest, and invite a small group of people who dig for records. Signing details stay out of the repository.

## Then (v0.3)

These make it better to use over a full day of digging.

7. **Cache sleeve thumbnails (4 h).** ([#7](https://github.com/banjonay1992/crate/issues/7)) Store thumbnails for the collection, wantlist and recent lookups on disk with a size cap, so offline results and the library lists show artwork.
8. **Quick add to wantlist and collection (5 h).** ([#8](https://github.com/banjonay1992/crate/issues/8)) Add and remove wantlist items and add to collection from the result screen (`PUT /users/{username}/wants/{release_id}` and the collection folder endpoint), including queued writes when offline and conflict handling on sync.
9. **Batch scanning mode (4 h).** ([#9](https://github.com/banjonay1992/crate/issues/9)) Keep the camera live and stack results in a list as you flick through a crate, with wanted and owned items highlighted, rather than navigating to a result for each record.
10. **Better matrix matching (4 h).** ([#10](https://github.com/banjonay1992/crate/issues/10)) Collect real run-out transcriptions from the field test and tune the partial matching: treat common etched symbols, mastering engineer initials and "1/2" stamper marks as optional tokens, and score the match instead of the current yes or no.
11. **Move storage to SQLite (6 h).** ([#11](https://github.com/banjonay1992/crate/issues/11)) Replace the JSON files for the release cache with a small SQLite store (using the system library through a thin wrapper, keeping CrateCore dependency-free) so a 5,000 item collection loads and searches without reading one large file. Migrate existing caches on first launch.
12. **Dig log statistics (3 h).** ([#12](https://github.com/banjonay1992/crate/issues/12)) Per shop totals over time, average price paid against market price at the time, and the share of wantlist finds per visit.

## Later

13. **OAuth sign-in (6 h).** ([#13](https://github.com/banjonay1992/crate/issues/13)) Implement the Discogs OAuth 1.0a flow with `ASWebAuthenticationSession` so users can sign in without copying a token. Requires registering the app with Discogs and keeping the consumer secret out of the repository.
14. **Want alerts by shop (3 h).** ([#14](https://github.com/banjonay1992/crate/issues/14)) When you type a shop name you have found wanted records at before, show a short list of your wants that match labels or styles you tend to find there.
15. **Widgets and Shortcuts (4 h).** ([#15](https://github.com/banjonay1992/crate/issues/15)) A Lock Screen widget that opens straight to the scanner, and an App Intent for "Look up catalogue number".
16. **Accessibility pass (3 h).** ([#16](https://github.com/banjonay1992/crate/issues/16)) Audit with VoiceOver, Dynamic Type at the largest sizes and Voice Control; make scan results announce the headline badge immediately.
17. **Localisation (2 h).** ([#17](https://github.com/banjonay1992/crate/issues/17)) Move strings to a String Catalog and provide the format strings needed for currencies and dates; start with British and American English.
