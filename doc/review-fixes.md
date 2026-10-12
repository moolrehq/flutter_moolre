# Review resolution record

> **Note (2026-10-12):** the in-app sandbox emulation described below (and its
> `SPV05` handling) was replaced. Sandbox now uses Moolre's hosted sandbox page
> through the documented `/embed/link` endpoint in an in-app browser, with
> status confirmed by `/open/transact/status`. See the README.

The attached review describes the former 0.0.1 WebView checkout. Version 0.1.0
replaces that flow with native Flutter mobile-money checkout and direct Moolre
API access. The merchant-backend adapter is optional. This cleanup checks the replacement against every finding.

## Attached findings

| # | Finding | Resolution |
| --- | --- | --- |
| 1 | Redirect/deep-link callbacks could report unpaid orders as successful | Removed URL-based success. Direct verification checks transaction status, external reference, amount, configured merchant account, and currency when present. The controller rejects unverified success and changed order/session details. |
| 2 | Incorrect verification endpoint/body and numeric status handling | The direct gateway uses `/open/transact/status` with `X-API-USER`, the configured account, `type: 1`, `idtype: 1`, and the original external reference. `X-API-PUBKEY` is optional in sandbox and required in live. API acceptance is separate from verified transaction success. |
| 3 | Customer redirect supplied as a server webhook | Hosted redirects removed. The direct demo checks provider status and needs no redirect or webhook. Production callback handling belongs to a trusted merchant service. |
| 4 | Native deep-link implementation missing from the package | Removed the deep-link API and bridges. Also removed unused platform method channels, native registration, Gradle library, and CocoaPods scaffolding. |
| 5 | Checkout destroyed the caller's route stack | The sheet returns a typed result and closes its own route. Result callbacks run after closure; tests preserve an intermediate order route. |
| 6 | Failed WebView resources aborted payments | WebView removed. Ambiguous networking failures retain a pending payment and are resolved by status. |
| 7 | iOS callback scheme checks lacked configuration | URL launching and custom schemes removed. HTTPS Moolre requests require no callback scheme configuration. |
| 8 | Android release networking permission missing | Example main manifest includes `INTERNET`. Installation instructions require it in consuming apps' main manifests; the package no longer has a native manifest to merge. |
| 9 | Unsafe HTTP/JSON handling and unbounded requests | Validate HTTP status, JSON shape, immutable session fields, and success verification. Bound authentication, transport, and streaming by one deadline; abort timed-out requests, reject redirects, and limit response bodies to 64 KiB. |
| 10 | Lifecycle, system-back, cancellation, and disposal gaps | Pause/resume polling, ignore late completions after disposal, and return the current result for system back. Closing an in-flight or unresolved saved session remains pending. |
| 11 | Duplicate callbacks or a throwing callback could block checkout | Deduplicate terminal sessions while mounted. Reset processing before callbacks and report callback exceptions through Flutter's error handler without changing payment outcomes or suppressing the other notification. |
| 12 | Ineffective and inactive flow tests | Replace old tests with injected gateways/HTTP clients, native widget flows, layout checks, direct-provider/recovery tests, and an opt-in real sandbox device integration test. |

Timestamp-only references were replaced with server UUIDs. Phone/OTP input,
session IDs, and request keys are validated. Money uses exact minor units.
Sandbox configuration, version-consistent installation/migration instructions,
and removal of unused dependencies are included.

## Additional fixes in the replacement

- Bound HTTP requests and streaming by a deadline; abort timed-out requests,
  reject redirects, and cap provider responses at 64 KiB.
- Persist the direct gateway's dispatch claim before contacting Moolre. Concurrent
  requests through one owner and app reopening recover the original reference.
- Reject changed reference/amount/account/currency, unverified success, boolean
  transaction-success values, and successful-looking non-2xx provider responses.
- Preserve pending status after networking errors or duplicate references.
  Expire unused ready/OTP attempts, never dispatched pending payments.
- Isolate local recovery and cart snapshots by environment, merchant and order.
  Disable cart editing while a payment is unresolved; changing amounts creates a
  new order. Empty carts cannot be paid.
- Replace the Node demo server with an editable cart and real direct API calls.
  The app no longer needs a local backend, app token or USB forwarding.
- Store the demo recovery file atomically in application support, with serialized
  writes. Never store OTPs or public keys in recovery records.
- Preserve caller-owned request keys and route stacks; isolate callback errors,
  ignore late results, and pause/resume sequential polling with app lifecycle.

## Validation and limits

The automated suites cover direct-provider contracts, persistence before dispatch,
lost responses, verification mismatches, mode isolation, request limits, native
checkout and cart editing. All HTTP clients in these tests are injected; tests
never collect money. The opt-in device integration test refuses live mode.

Client-side verification and local recovery do not make production fulfilment
trustworthy or provide an always-running reconciliation worker. Production
merchants must independently validate real orders on a trusted server. An
existing backend can use the optional `MoolrePaymentService` contract.
Unknown transaction statuses remain pending until confirmed against Moolre's
contract. iOS builds have not been run. The real hosted sandbox was checked
with test-only OTP, Pending and Failed requests; no live collection was initiated.
On 2026-10-12, the deployed sandbox Success operation returned HTTP 500 / `SPV05`
(`Failed to update sandbox wallet balance`). The original reference remained
unconfirmed on status lookup. Checkout now reports that provider error while
preserving pending recovery; it never substitutes local success. The provider
wallet-credit failure needs to be resolved on Moolre's sandbox service.

The removed demo server, its private environment file and SQLite data were
preserved outside the repository. Two previous attempts remained unresolved
when their original references were checked; they were not automatically imported
as new direct-cart orders. Retain those records for reconciliation. The new local
recovery handles attempts created by the direct gateway.

The backend-removal migration did not initiate payments. Subsequent sandbox-flow
validation created test-only sandbox attempts.
