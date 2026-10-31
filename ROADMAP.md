# Roadmap

Estimates are rough working hours for one developer. The total is about 60 hours.

## Next

These make the first version trustworthy in a real shop.

1. **Field test on a device (4 h).** Run the scanner against 50 real sleeves in varied light, including shrink-wrapped and glossy ones. Record misreads, how long a lookup takes on 3G and with no signal, and which UPC-E codes come through from AVFoundation as 6, 7 or 8 digits. Fix what turns up.
2. **Check every endpoint against the live API (3 h).** With a throwaway Discogs account, capture real responses for search, release, marketplace stats, price suggestions, collection and wants. Save sanitised copies as new fixtures and add tests for any field shape the invented fixtures got wrong, especially the error body for price suggestions without seller settings.
3. **App-level tests (5 h).** Add an app test target. Unit test `AppModel` with an in-memory store and a mock `DiscogsAPI` (connect, disconnect clearing the cache, sync error handling, queue draining when connectivity returns). Add one UI test that types a catalogue number in manual entry and reaches the pressing chooser, and run both in CI on a named simulator.
4. **Rate limit visibility (2 h).** Surface a short "Discogs asked Crate to slow down" banner when the limiter is pausing for more than a few seconds, so a long sync does not look frozen. Add a test for the pause reporting.
5. **Scan confirmation step (2 h).** Before running a lookup, show the decoded digits for half a second with an undo, so an accidental scan of the wrong sleeve in a stack does not cost a request.

## Then

These make it better to use over a full day of digging.

6. **Cache sleeve thumbnails (4 h).** Store thumbnails for the collection, wantlist and recent lookups on disk with a size cap, so offline results and the library lists show artwork.
7. **Quick add to wantlist and collection (5 h).** Add and remove wantlist items and add to collection from the result screen (`PUT /users/{username}/wants/{release_id}` and the collection folder endpoint), including queued writes when offline and conflict handling on sync.
8. **Batch scanning mode (4 h).** Keep the camera live and stack results in a list as you flick through a crate, with wanted and owned items highlighted, rather than navigating to a result for each record.
9. **Better matrix matching (4 h).** Collect real run-out transcriptions from the field test and tune the partial matching: treat common etched symbols, mastering engineer initials and "1/2" stamper marks as optional tokens, and score the match instead of the current yes or no.
10. **Move storage to SQLite (6 h).** Replace the JSON files for the release cache with a small SQLite store (using the system library through a thin wrapper, keeping CrateCore dependency-free) so a 5,000 item collection loads and searches without reading one large file. Migrate existing caches on first launch.
11. **Dig log statistics (3 h).** Per shop totals over time, average price paid against market price at the time, and the share of wantlist finds per visit.

## Later

12. **OAuth sign-in (6 h).** Implement the Discogs OAuth 1.0a flow with `ASWebAuthenticationSession` so users can sign in without copying a token. Requires registering the app with Discogs and keeping the consumer secret out of the repository.
13. **Want alerts by shop (3 h).** When you type a shop name you have found wanted records at before, show a short list of your wants that match labels or styles you tend to find there.
14. **Widgets and Shortcuts (4 h).** A Lock Screen widget that opens straight to the scanner, and an App Intent for "Look up catalogue number".
15. **Accessibility pass (3 h).** Audit with VoiceOver, Dynamic Type at the largest sizes and Voice Control; make scan results announce the headline badge immediately.
16. **Localisation (2 h).** Move strings to a String Catalog and provide the format strings needed for currencies and dates; start with British and American English.
