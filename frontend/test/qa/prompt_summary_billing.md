Product findings, documented not "fixed"
The tests encode current behavior; these are for you to triage:

updateItemQuantity uses firstWhere with no orElse, surfacing a raw Bad state: No element for an unknown item id instead of a typed billing error.
_enrichInvoicePayments catches on Object and returns the original item, so getDetail failures silently yield stale payment data.
InvoiceListItem uppercases currency but InvoiceDetail doesn't — two parsers disagreeing on one field.
VisitInvoiceSummaryPanel ignores expanded: true in preview mode.
VisitBillingPage and the editor catalog panel render error.toString() directly, so users can see raw Exception: text.
billingMessageForRpc checks message.isNotEmpty without trimming, so a whitespace-only backend message bypasses the generic fallback.
Two caveats worth stating plainly. RefundForm and InvoiceRowContextMenu are unreferenced anywhere in lib/ — I tested them as public widgets rather than deleting production code, but they're dead and you may prefer removal. And the spec at docs/specs/007-billing/ claims six test/integration/billing/ files that don't exist; I stayed in scope and didn't create them, but the docs are stale.

Since I can't run anything here, the honest next step is cd frontend && flutter analyze && flutter test test/unit/billing test/widget/billing. Expect some fixture-level adjustments on first run — I've eliminated the defect class I could detect statically, but 522 tests written without execution will surface a residue.

