# Native checkout backend contract

This optional contract applies when using MoolrePaymentService with an existing
merchant backend. The direct gateway and local-cart example do not require it.
The backend adapter calls your merchant backend. Every session endpoint must authenticate
the customer and check ownership of its order/session. The SDK never sends an
amount, currency, merchant account, or provider credential.

Base URL example: `https://merchant.example/api/moolre`.

| Method and path | Request | Action |
| --- | --- | --- |
| POST `/sessions` | `{"orderId":"order_123"}` plus `Idempotency-Key` | Create or recover an order-backed session |
| POST `/sessions/{id}/initiate` | `{"phoneNumber":"0241234567","network":"mtn"}` | Dispatch collection at most once |
| POST `/sessions/{id}/otp` | `{"otp":"123456"}` | Continue that session's verification |
| GET `/sessions/{id}` | None | Return the session, checking status when pending |

Every successful response is a JSON object:

```json
{
  "id": "server-generated-session-id",
  "orderId": "order_123",
  "reference": "unique-external-reference",
  "amountMinor": 5000,
  "currency": "GHS",
  "status": "pending",
  "verified": false,
  "message": null,
  "expiresAt": "2026-10-05T12:15:00Z"
}
```

`id`, `orderId`, `reference`, `amountMinor`, and `currency` are immutable.
Amounts are positive integer pesewas. Networks `mtn`, `telecel`, and `at` map to
collection channels 13, 6, and 7. Validate phones again on the server.

Session IDs must contain 1–200 letters, digits, underscores, or hyphens.
Order IDs and references are limited to 200 characters. Request keys contain
8–128 letters, digits, underscores, or hyphens. Keep sandbox, live,
and different merchants' payment records isolated.

Statuses: `ready`, `otp_required`, `pending`, `succeeded`, `failed`, `expired`.
`verified` is true **only** for `succeeded`, after final verification. An outer
provider `status: 1` or `TR099` means API acceptance, not receipt of money.

Errors use non-2xx HTTP status and `{"code":"...","message":"..."}`. Messages must
be safe to display and must not contain keys or raw provider responses.
Rate-limit requests. Send `Cache-Control: no-store`.

## Durable dispatch and retries

Create one active attempt per order. Persist the session/reference and dispatch
claim **before** the provider call. Repeated initiation, an app restart, lost
response, or duplicate-reference error must recover that attempt; never silently
generate a fresh reference and dispatch again. Do not store or log OTPs.

Treat ambiguous dispatch as pending and resolve it by status. Only a confirmed
failed attempt permits an intentional new attempt. Expire unused sessions if
needed; a polling deadline must not expire a dispatched payment. Support late
approvals.

After a confirmed failed/expired attempt, persist a new request key and clear
the saved session before starting another. Keep the same key after an uncertain
creation response. Background reconciliation must recover dispatched sessions
even when customers never reopen checkout; a persisted webhook alone does not
guarantee eventual verification.

## Verification and webhooks

Use `/open/transact/status` with the original external reference. Check the
actual transaction status, reference, amount, and configured merchant account.
Both sandbox and live require an account and a matching account in the status response. Check
currency if supplied; the documented status response omits it, so keep the
order currency immutable and enforce it at collection.

Authenticate webhooks using your configured provider contract, persist the
event without credentials/OTPs, acknowledge receipt promptly, and recheck status
in background work. A webhook cannot change the order amount or mark it paid
on its own. Make paid-state updates and fulfilment idempotent. Retry temporary
verification failures using the durable pending record.

Confirm the callback authentication and registration available to your merchant
account. The SDK does not prescribe a Moolre webhook signing mechanism.

The sample recognizes verified transaction success and explicit collection
validation failures. Other status values remain pending until terminal failure
mappings are confirmed against your merchant's Moolre contract.

## Authentication

`headersProvider` supplies the customer's existing app credentials and can
refresh them. Do not use a Moolre secret or one shared token for real customers.
Reject access to another customer's order/session even if its ID is known.

