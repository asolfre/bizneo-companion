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
