# PostgreSQL migration runbook — Block 2 packet identity (`raw_packets`)

**What changes.** `raw_packets.packet_id` used to be UNIQUE on its own (index
`ix_raw_packets_packet_id`, unique). Block 2 makes identity `UNIQUE(sender_id, packet_id)`
(`uq_raw_packets_sender_packet`) and turns `ix_raw_packets_packet_id` into a plain (non-unique)
index. New tables (`rejected_packets`, `signed_request_nonces`, `sms_notifications`) are added by
`create_all()`; no existing column is altered or dropped, **no row is modified or deleted**.
`init_db()` runs `upgrade_raw_packet_identity()` at every boot; it is idempotent.

**Verification status (be exact).**
* VERIFIED on a real **PostgreSQL 18.4** (embedded server, scratch database, this environment):
  `Backend/tests/test_postgres_integration.py` — legacy schema upgraded with every row preserved,
  old single-column guarantee proven before / new composite proven after, idempotence, transactional
  behaviour (a failing upgrade leaves the old unique index intact), documented rollback (works only
  without cross-sender `packet_id` reuse), the ingest pipeline including `pg_advisory_xact_lock`
  and dedup, and 8 concurrent identical uploads ⇒ exactly one ACCEPT, no 5xx.
* **NOT verified against the production database** (no access). PostgreSQL 18.4 is not necessarily the
  production version (Neon/Render): run the procedure below on a **copy** first.

## Procedure (never run destructive steps against production first)

1. **Freeze risk / backup.** Take a snapshot (Neon: create a branch; otherwise
   `pg_dump -Fc "$DATABASE_URL" > setu-pre-block2.dump`). Confirm you can restore it.
2. **Rehearse on a copy.** Create a scratch database from the snapshot (Neon branch / `pg_restore`).
   Point a shell at it (`DATABASE_URL=<scratch>`).
3. **Pre-flight checks (read-only)** on the copy:
   ```sql
   -- current uniqueness on packet_id (expect the old unique index)
   SELECT indexname, indexdef FROM pg_indexes WHERE tablename='raw_packets';
   -- rows that would violate the NEW constraint (must be 0; the old constraint makes it impossible)
   SELECT sender_id, packet_id, count(*) FROM raw_packets GROUP BY 1,2 HAVING count(*)>1;
   -- legacy squatter rows (unauthenticated packets stored by the old code); informational
   SELECT status, count(*) FROM raw_packets GROUP BY status;
   SELECT count(*) AS rows_before FROM raw_packets;
   ```
4. **Apply on the copy:** `cd Backend && python -m app.db.init_db` (or start the app once).
   It runs inside one transaction per statement group; a failure rolls back and keeps the old index.
5. **Verify on the copy:**
   ```sql
   SELECT indexname, indexdef FROM pg_indexes WHERE tablename='raw_packets';
   --   ix_raw_packets_packet_id  : NOT unique
   --   uq_raw_packets_sender_packet : UNIQUE (sender_id, packet_id)
   SELECT count(*) AS rows_after FROM raw_packets;   -- must equal rows_before
   ```
   then `SETU_TEST_POSTGRES_URL=<scratch url whose db name contains "test" or "scratch"> pytest tests/test_postgres_integration.py`
   (the test refuses any other database name — it drops the public schema).
6. **Production window.** Repeat steps 1, 3, 4, 5 on production during low traffic. The index build
   takes a short `SHARE` lock on `raw_packets` (writes to `/ingest` wait for it; reads are unaffected). On a
   very large table build the composite index first with `CREATE UNIQUE INDEX CONCURRENTLY
   uq_raw_packets_sender_packet ON raw_packets (sender_id, packet_id);` (outside a transaction), then
   let `init_db` drop the old index — it sees the new one and skips creating it.
7. **Deploy order.** Migrate → deploy backend → release the app (Block 2/3 endpoints require signed requests).

## Rollback expectations
* Before any packet with a reused `packet_id` from a different sender exists, rollback is:
  ```sql
  BEGIN;
  DROP INDEX uq_raw_packets_sender_packet;   -- (or ALTER TABLE ... DROP CONSTRAINT if it was created by create_all)
  DROP INDEX ix_raw_packets_packet_id;
  CREATE UNIQUE INDEX ix_raw_packets_packet_id ON raw_packets (packet_id);
  COMMIT;
  ```
* **After** two senders have used the same `packet_id` this rollback FAILS (unique violation) and leaves the
  new index in place — verified by the test. That is the point of no return; roll forward instead.
* The old code must not be redeployed against the migrated schema without this rollback (it would
  treat an authentic same-id packet from another sender as a duplicate again).
* Restoring the pre-migration snapshot is always available and loses only data written after it.

## Transaction behaviour
DDL is transactional in PostgreSQL: each `init_db` step either fully applies or rolls back. The ingest
path commits once per packet; duplicates racing on `(sender_id, packet_id)` are resolved by the constraint
(`IntegrityError` → re-read → DUPLICATE / conflict / retryable FAILED), never a 500.
