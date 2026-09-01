# Plan: Show pending change-requests from past months

## Problem

The "Pending changes (N)" menu section disappears after a month rollover, even
though unapproved change-requests from a previous month are still counted in the
**This year** figure.

Root cause (verified):
- The menu section is built from `snapshot.pending` (StatusItemController: the
  `s.pending.filter { $0.proposedMin != nil }` block).
- `snapshot.pending` is `resolvePending(in: days)` where `days` = **current month
  only** (`BizneoClient.refresh`). So on e.g. July 1, a June request isn't in the
  list → section hidden.
- The **year** still shows the pending delta because `computeYear` sums each cached
  past-month's `pendingDeltaMin` (`yearCache[m].pendingDeltaMin`). The individual
  `PendingRequest` objects are discarded — only the summed delta is kept.

Result: `This year: … (pending +6:59)` with no visible list explaining it.

## Fix

Surface pending items from the whole year, not just the current month.

1. **`BizneoClient` — retain per-month pending requests in the cache**
   - Change `MonthTotal` to also carry the requests:
     ```swift
     private struct MonthTotal {
         var balanceMin: Int
         var pendingDeltaMin: Int
         var pending: [PendingRequest]
     }
     ```
   - In `computeMonthTotal`, keep the `[PendingRequest]` it already resolves (it
     currently computes `delta` from them and throws them away) and store on
     `MonthTotal`.

2. **`refresh()` — aggregate current + cached past-month pending**
   - After building the current-month `pending` and the year, merge:
     ```swift
     var allPending = pending                                  // current month
     for m in yearCache.values { allPending += m.pending }     // cached past months
     ```
   - Dedup by `id`, sort by `dateString`, and set as `snapshot.pending`.
   - Keep the period `pendingDeltaMin` math unchanged (today/week/month use their own
     date-scoped deltas; year already includes past-month deltas).

3. **Menu** — no change needed; the existing "Pending changes (N)" section will
   render the aggregated list again and match the year's pending figure.

## Tests

- `--selftest` is fixture-based (single month), so existing checks stay valid.
- Optionally add a check that merging current + a synthetic past-month pending list
  dedups by id and sorts by date.

## Caveats / notes

- Cached past-month pending only re-resolves when the year cache refreshes
  (~3h TTL / relaunch / year rollover). So an approval/rejection in a past month
  lingers in the list until then. Acceptable; document if surfaced.
- Requires `enableYearTotal` to populate `yearCache`; if year total is disabled,
  past-month pending won't be available (fall back to current-month only).

## Deviations at implementation time

1. **The merge is a pure function, `Calculator.mergePending`, not inline code in
   `refresh()`.** As planned, the whole fix would have lived inside
   `BizneoClient.refresh()` — which needs the Chrome cookie, the Keychain and the
   network, and is therefore unreachable from both `--selftest` and `ParserTests`
   (the test target depends only on `BizneoCore` and never builds a `BizneoClient`).
   The plan's "optionally add a check" would in practice have meant shipping the
   behaviour untested. Extracting dedup+sort leaves exactly one untestable wiring
   line in the client and puts the logic under test in both files.
2. **Dedup is "first list wins", and the current month is passed first.** The plan
   just said "dedup by `id`". Which copy survives matters: past months refresh only
   every 3h (`yearCacheTTL`) while the current month is re-resolved every pass, so a
   cached copy is by definition the staler one. `mergePending` is documented as
   earlier-lists-win and the call site passes `[pending] + yearCache.values…`.
3. **`PendingRequest` was left `Equatable`.** The plan implied a `Set`-based dedup;
   the type is not `Hashable` (`Models.swift:39`), so `mergePending` tracks a
   `Set<String>` of ids instead. No conformance was added.

Two behaviours worth knowing, neither of them fixed here:

- **December → January.** `computeYear` returns early when `currentMonth == 1`
  (`BizneoClient.swift:198`), so a December request will not appear in January. This
  is consistent rather than broken: the year total resets at the same moment, so the
  list and the figure still agree.
- **A month whose fetch fails is cached as zeros for up to 3h**
  (`BizneoClient.swift:201-202`), so its requests silently won't be listed. That is
  pre-existing behaviour for the year balance; the pending list now inherits it.

### Verification gap

The end-to-end path could not be exercised: `--probe` reaches live Bizneo, but the
account had **no open change-requests at all** when this shipped, so a before/after
comparison would have shown two empty lists either way. Evidence for this fix is the
unit tests, which were mutation-checked — dropping the sort and inverting the dedup
precedence each fail the specific assertion aimed at them. The one line the tests do
not cover is the `snapshot.pending` assignment in `refresh()`.
