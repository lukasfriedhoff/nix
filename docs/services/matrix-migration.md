# Matrix Migration: `docker-host` to Production

This runbook records the reusable workflow for migrating the legacy Matrix
stack from `docker-host:/mnt/dockerstorage/matrix` to the production Synapse
homeserver `h4xx.io`.

The migration changes the homeserver name and maps the interactive user from
`@lukas:m.h4.ddnss.org` to `@lukasf:h4xx.io`. Synapse does not support changing
`server_name` in place, so this remains an operator-controlled rewrite with
explicit backups, disposable tests, audit-first repairs, and a reversible
cutover.

The migration and verification helpers live in the `flux-cluster` repository,
not this Nix repository:

```sh
export FLUX_CLUSTER_REPO=/path/to/flux-cluster
cd "$FLUX_CLUSTER_REPO"
```

## Safety Contract

- Keep the source stack and its storage intact until production parity is
  accepted.
- Test a fresh source dump in an isolated namespace before every production
  migration attempt.
- Take source database dumps, production CNPG backups, bridge database
  backups, and media manifests at named checkpoints.
- Never rewrite `public.event_json.json`. Its signed event payloads are tied to
  content-addressed event IDs.
- Never apply stream-wide text replacement to a SQL restore.
- Use supported Synapse admin and Matrix client APIs for room repairs. Do not
  modify event, state, membership, or power-level tables directly.
- Treat room-ID inventories as migration artifacts. Generate exact inventories
  and review them before any apply operation.
- Keep secrets in SOPS-managed files or mounted secret files. Do not place
  access tokens, passwords, or recovery keys in shell history, logs, or this
  document.
- Do not expose a scratch Synapse publicly. Keep its egress isolated while
  rewritten federation behavior remains unverified.

## Repositories and Secret References

Production Matrix and bridge configuration is managed through the homelab
overlay in `flux-cluster`. Relevant encrypted inputs include:

- `overlays/homelab/secrets/matrix-synapse-config.yaml`
- `overlays/homelab/secrets/matrix-whatsapp-config.yaml`
- `overlays/homelab/secrets/matrix-signal-config.yaml`
- the corresponding appservice registrations and database credentials in
  `overlays/homelab/secrets/`

Runtime repair commands should use mounted files such as:

- `ACCESS_TOKEN_FILE=/run/secrets/synapse-admin-token`
- `ACCESS_TOKEN_FILE=/run/secrets/temporary-synapse-admin-token`
- `--access-token-file /run/secrets/retired-matrix-access-token`

Use environment variables to select hosts, namespaces, contexts, and target
identities. Never set `ACCESS_TOKEN` directly when a file is available.

## Helper Inventory

| Helper | Default behavior | Mutating operation |
| --- | --- | --- |
| `scripts/matrix-server-name-rewrite.sh` | Runs only the named command against a guarded scratch namespace | `all-db`, `copy-media`, and `deploy-synapse` create or replace scratch resources |
| `scripts/repair-matrix-migrated-room-admins.sh` | `inventory` | `repair` grants a reviewed current-domain user room administrator power through Synapse |
| `scripts/repair-matrix-whatsapp-migrated-rooms.sh` | `inventory` | `repair` grants the current WhatsApp bridge bot power only where the current user is already an administrator |
| `scripts/repair-matrix-migrated-history-visibility.sh` | `inventory` | `repair` emits and verifies a signed `m.room.history_visibility` event |
| `scripts/clear-matrix-migrated-room-names.sh` | `inventory` | `apply` clears only an exact matching unsafe explicit room-name event |
| `scripts/retire-matrix-migrated-direct-memberships.py` | Audit only | `--apply` makes the retired account leave exact, prevalidated direct-message rooms |
| `scripts/repair-matrix-migrated-media-cache.py` | Dry run | `--apply` hardlinks retained-origin media into Synapse's remote-cache layout and updates cache metadata |

Run the matching `scripts/verify-matrix-*.sh` or
`scripts/verify-matrix-*.py` test before using a changed helper against live
data.

## Phase 1: Inventory and Checkpoint

1. Confirm the legacy stack on `docker-host` is healthy enough to produce
   consistent dumps.
2. Record source container versions and the exact Synapse and bridge database
   names.
3. Inventory source counts:
   - Synapse users, rooms, events, and local media records;
   - media files and total bytes;
   - WhatsApp and Signal portal/message mappings;
   - bridge history, backfill, and offline-sync queue depth.
4. Inventory the production target:
   - CNPG cluster health and latest successful backups;
   - Synapse media PVC health and free space;
   - current appservice registrations;
   - joined rooms for `@lukasf:h4xx.io`;
   - current bridge identities and room power.
5. Create a checkpoint containing:
   - a fresh source Synapse database dump;
   - source bridge database dumps;
   - source media file/size manifest;
   - production CNPG on-demand backups;
   - production media volume backup or snapshot;
   - reviewed room-ID inventories for later repairs.
6. Verify every backup can be listed and has a non-zero object count before
   proceeding.

Do not stop the source stack for the initial test. `pg_dump` provides a
consistent database snapshot while the source remains available.

## Phase 2: Disposable Rewrite Test

Use a unique namespace and work directory. Never use the live `matrix`
namespace for this phase.

```sh
export SOURCE_HOST=docker-host
export SOURCE_DIR=/mnt/dockerstorage/matrix
export OLD_SERVER=m.h4.ddnss.org
export NEW_SERVER=h4xx.io
export KUBECONTEXT=homelab-prod
export NAMESPACE=matrix-rewrite-prod-dryrun
export WORK_DIR="$FLUX_CLUSTER_REPO/.matrix-rewrite/prod-h4xx"
export STORAGE_CLASS=longhorn-ssd-rwo-2r
export POSTGRES_SIZE=12Gi
export MEDIA_SIZE=60Gi

scripts/matrix-server-name-rewrite.sh all-db
scripts/matrix-server-name-rewrite.sh copy-media
scripts/matrix-server-name-rewrite.sh deploy-synapse
scripts/matrix-server-name-rewrite.sh validate
```

`all-db` performs the source dump, dump inventory, scratch provisioning,
restore, ownership repair, and mutable-field rewrite. It deliberately
preserves signed event JSON.

`copy-media` compares file/size manifests and copies only missing or
size-mismatched files in batches. It is resumable and safe to repeat. Adjust
`MEDIA_COPY_BATCH_SIZE` when needed.

Health alone is not sufficient. Validate with a disposable scratch account so
authenticated `/sync` loads retained events:

```sh
export MATRIX_TEST_ACCESS_TOKEN_FILE=/run/secrets/matrix-scratch-access-token
export MATRIX_TEST_ACCESS_TOKEN="$(<"$MATRIX_TEST_ACCESS_TOKEN_FILE")"
scripts/matrix-server-name-rewrite.sh validate
unset MATRIX_TEST_ACCESS_TOKEN
```

Acceptance criteria:

- Synapse starts without `DatabaseCorruptionError`;
- authenticated `/sync` succeeds and reports joined rooms;
- source and scratch event counts are explainable;
- old server-name references remain only where expected in signed event JSON;
- copied media counts and bytes match the source manifest;
- the scratch deployment cannot send rewritten federation traffic; and
- the helper safety tests pass:

```sh
scripts/verify-matrix-rewrite-safety.sh
scripts/verify-matrix-migrated-media-cache.py
scripts/verify-matrix-migrated-room-admin-repair.sh
scripts/verify-matrix-migrated-history-visibility.sh
scripts/verify-matrix-migrated-room-name-clear.sh
scripts/verify-matrix-migrated-membership-retirement.py
scripts/verify-matrix-whatsapp-room-repair.sh
```

Delete only the disposable namespace after preserving the validation report:

```sh
scripts/matrix-server-name-rewrite.sh delete-scratch
```

## Phase 3: Production Preparation

The rewrite helper is a scratch harness, not a turnkey production deployment
tool. Production application remains a controlled CNPG restore and GitOps
cutover using the validated dump/rewrite strategy.

Before applying:

1. Reconcile the production Matrix manifests and SOPS secrets.
2. Pin the validated Synapse and bridge versions for the cutover.
3. Ensure production storage has enough headroom for the database, media, WAL,
   and repair operations.
4. Choose exactly one canonical WhatsApp bridge and one canonical Signal
   bridge.
5. Back up each canonical bridge database and retain its matching appservice
   registration.
6. Disable duplicate bridge deployments and registrations through GitOps.
   Never run two bridge instances against the same remote account or database.
7. Confirm the new interactive identity is `@lukasf:h4xx.io`.
8. Keep the old MXID in signed historical events. Do not attempt to replace it
   inside retained event JSON.

## Phase 4: Initial Production Copy

Perform the initial target restore while the source remains available:

1. Restore the validated Synapse dump into the production database workflow.
2. Apply only the mutable-field rewrite proven by the scratch test.
3. Restore the canonical bridge databases with their matching appservice
   registrations.
4. Copy the Synapse media store using the same manifest-based process as the
   scratch test.
5. Start Synapse privately and validate health plus authenticated `/sync`.
6. Start each bridge only after its database, registration, and current-domain
   bot identity agree.
7. Keep public DNS and ingress on the old service until the target acceptance
   checks pass.

At this point, source and target will diverge if both accept writes. This phase
is for validation, not final cutover.

## Phase 5: Bridge Consolidation and Login

For each bridge:

1. Confirm there is one deployment, one registration, one database, and one
   current-domain bot identity.
2. Run the GitOps verification helpers:

```sh
scripts/verify-matrix-bridge-history-import.sh homelab
scripts/verify-matrix-whatsapp-registration.sh homelab
```

3. Reconcile encrypted bridge configuration before logging in.
4. Use the bridge bot's supported login flow and approve the linked device on
   the phone.
5. Wait for initial history/offline sync to finish before changing portals or
   room power.
6. Verify one inbound and one outbound message, media in both directions, and
   bridge database mappings.
7. Grant a current-domain bridge bot room power only after
   `@lukasf:h4xx.io` is a joined administrator.

For migrated WhatsApp rooms:

```sh
ACCESS_TOKEN_FILE=/run/secrets/synapse-admin-token \
ADMIN_USER_ID='@lukasf:h4xx.io' \
BRIDGE_USER_ID='<current WhatsApp bridge MXID>' \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-whatsapp-migrated-rooms.sh inventory \
  retained-whatsapp-room-ids.txt

ACCESS_TOKEN_FILE=/run/secrets/synapse-admin-token \
ADMIN_USER_ID='@lukasf:h4xx.io' \
BRIDGE_USER_ID='<current WhatsApp bridge MXID>' \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-whatsapp-migrated-rooms.sh repair \
  retained-whatsapp-room-ids.txt
```

Do not relink repeatedly when history queues are empty and offline sync reports
zero new events. Relinking cannot request arbitrary historical messages and
may create replacement portal rooms. The default migration keeps retained
rooms and repairs them in place.

## Phase 6: Matrix Media

The media copy and the retained-origin cache repair solve different problems:

- the copy transfers the bytes from the legacy `synapsemedia` store;
- the cache repair makes signed `mxc://m.h4.ddnss.org/...` references
  resolvable after the homeserver rename.

Take a fresh production database backup before the cache repair. Run the tool
inside the new Synapse container:

```sh
python /tmp/repair-matrix-migrated-media-cache.py \
  --origin m.h4.ddnss.org

python /tmp/repair-matrix-migrated-media-cache.py \
  --origin m.h4.ddnss.org \
  --apply
```

The apply operation hardlinks local media and thumbnails into the remote-cache
layout and updates `remote_media_cache` metadata transactionally. It is
idempotent and should not duplicate file data.

Verify:

```sh
scripts/verify-matrix-migrated-media-cache.py
```

If an encrypted image remains unreadable after the object is reachable, the
client likely lacks the corresponding Megolm key. The media-cache repair
cannot reconstruct encryption keys.

## Phase 7: Room Identity, Power, Titles, and History

### Grant the current user room power

Inventory first, then repair only reviewed retained rooms:

```sh
TARGET_USER_ID='@lukasf:h4xx.io' \
ACCESS_TOKEN_FILE=/run/secrets/synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-migrated-room-admins.sh inventory \
  retained-room-ids.txt

TARGET_USER_ID='@lukasf:h4xx.io' \
ACCESS_TOKEN_FILE=/run/secrets/synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-migrated-room-admins.sh repair \
  retained-room-ids.txt
```

The API refuses rooms with no joined current-domain administrator. Keep these
rooms in an unresolved inventory rather than weakening the safety check.

### Expose retained history

For rooms using `joined` history visibility, use a short-lived repair account
to emit a signed `shared` state event:

```sh
REPAIR_USER_ID='@migration-repair:h4xx.io' \
ACCESS_TOKEN_FILE=/run/secrets/temporary-synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-migrated-history-visibility.sh inventory \
  retained-room-ids.txt

REPAIR_USER_ID='@migration-repair:h4xx.io' \
ACCESS_TOKEN_FILE=/run/secrets/temporary-synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/repair-matrix-migrated-history-visibility.sh repair \
  retained-room-ids.txt
```

Delete or deactivate the temporary account after verification.

`You don't have access to this message` is ambiguous after a migration. Do not
infer the cause from the client text alone:

1. capture the exact room and denied event ID from the client and Synapse logs;
2. confirm authenticated `/messages` or `/sync` returns the event;
3. inspect membership and history-visibility state at that event;
4. when the returned event is `m.room.encrypted`, compare its
   `session_id` with the current account's key backup;
5. when the server does not return the event, inspect the event's state group
   and auth chain; and
6. stop before changing database state directly.

If the event is delivered but the client lacks its Megolm session, the problem
is encryption-key availability, even when Element renders the generic access
message rather than `Unable to decrypt`. Synapse cannot recreate those private
keys.

### Recover encrypted history keys

Recover room keys only from a surviving legacy client or its valid encrypted
key backup. The preferred operator workflow is:

1. copy the legacy Element profile to a disposable, owner-only work directory;
2. start the copy with an isolated browser/display profile so the live client
   remains untouched;
3. verify the isolated client reports the expected legacy MXID and homeserver;
4. export E2EE room keys through Element's supported Security and Privacy UI,
   or the Matrix SDK's `exportRoomKeysAsJson` API;
5. store the export only in a mode-`0600` temporary file;
6. import it into a logged-in device for the replacement MXID with Element's
   import UI or `importRoomKeysAsJson`;
7. confirm the replacement account's existing trusted key backup is active;
8. wait for the backup upload queue to reach zero;
9. verify representative old sessions now exist in the replacement account's
   backup and decrypt in a separate current client; and
10. securely remove plaintext exports, temporary access tokens, disposable
    profiles, and temporary devices after acceptance.

Do not copy rows between Synapse key-backup tables. The backup payload is
encrypted for a user-controlled recovery key, and direct row copying does not
establish a valid trusted backup for the replacement account.

### Preserve participant-safe direct-message titles

Do not set a conversation partner's name as `m.room.name`. Room names are
shared state and every participant sees the same explicit title.

If a previous repair wrote explicit titles, clear only exact matching events:

```sh
ACCESS_TOKEN_FILE=/run/secrets/temporary-synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/clear-matrix-migrated-room-names.sh inventory \
  unsafe-room-names.tsv

ACCESS_TOKEN_FILE=/run/secrets/temporary-synapse-admin-token \
SYNAPSE_URL="$SYNAPSE_URL" \
  scripts/clear-matrix-migrated-room-names.sh apply \
  unsafe-room-names.tsv
```

When no explicit name exists, Element derives a participant-aware title. If
both the old and new identities remain joined, that title can include both.
Retire the old identity only from exact reviewed direct-message rooms:

```sh
scripts/retire-matrix-migrated-direct-memberships.py \
  --retired-user '@lukas:m.h4.ddnss.org' \
  --replacement-user '@lukasf:h4xx.io' \
  --access-token-file /run/secrets/retired-matrix-access-token \
  --synapse-url "$SYNAPSE_URL" \
  retained-direct-room-ids.txt

scripts/retire-matrix-migrated-direct-memberships.py \
  --retired-user '@lukas:m.h4.ddnss.org' \
  --replacement-user '@lukasf:h4xx.io' \
  --access-token-file /run/secrets/retired-matrix-access-token \
  --synapse-url "$SYNAPSE_URL" \
  --apply \
  retained-direct-room-ids.txt
```

The apply operation is intentionally limited to the retired account's leave
endpoint. A room is blocked when it is not in the retired account's `m.direct`
data, has an explicit name, lacks the replacement member, or gives the
replacement less power than the retired account. Review blocked rooms
individually.

## Phase 8: Incremental Sync and Final Cutover

### What is incremental

- `copy-media` is manifest-based and safe to rerun.
- Matrix `/sync` incrementally delivers new Matrix events that already exist
  on the connected homeserver.
- Bridge offline sync incrementally delivers events the remote service makes
  available.
- The repair helpers are inventory-first and idempotent.

### What is not incremental

- The Synapse database rewrite is not an append-only merge into a live target.
- A second database restore does not safely merge two independently written
  homeservers.
- Matrix `/sync` cannot backfill arbitrary old Signal or WhatsApp history.
- A bridge relink is not a general-purpose historical resync.
- Standard Synapse cannot insert bridge history into the middle of an existing
  populated portal timeline.
- Recopying a database or media store cannot recover events a bridge never
  submitted.

### Final-sync procedure

1. Announce the write freeze and record the final checkpoint name.
2. Confirm the target has a recent successful CNPG backup.
3. Stop write-producing source services: Synapse and all bridges. Keep the
   source databases and storage intact.
4. Create fresh final Synapse and bridge database dumps.
5. Force a fresh source Synapse dump rather than reusing the initial file:

```sh
FORCE_DUMP=true \
SOURCE_HOST=docker-host \
SOURCE_DIR=/mnt/dockerstorage/matrix \
OLD_SERVER=m.h4.ddnss.org \
NEW_SERVER=h4xx.io \
WORK_DIR="$FLUX_CLUSTER_REPO/.matrix-rewrite/prod-h4xx-final" \
  scripts/matrix-server-name-rewrite.sh dump-source
```

6. Rerun the manifest-based media copy until no files are missing or
   size-mismatched.
7. Restore and rewrite the final databases using the already validated
   production procedure. Do not improvise a live SQL merge.
8. Reconcile production GitOps and start Synapse privately.
9. Validate authenticated `/sync`, room/event parity, media parity, and bridge
   database mappings.
10. Start the canonical bridges and verify current-domain bot identities.
11. Switch ingress and discovery to production only after all acceptance
    checks pass.
12. Keep the stopped source stack and checkpoint backups unchanged through the
    rollback window.

If source services cannot be stopped, do not call the result a final sync.
Document the divergence window and schedule another controlled cutover.

## Phase 9: Verification

### Synapse

- health endpoint succeeds;
- authenticated `/sync` succeeds with a non-zero joined-room count;
- source immutable event IDs are present on the target;
- source and target media IDs and byte counts match;
- no `DatabaseCorruptionError`, event-auth corruption, or repeated 5xx errors;
- current public discovery points at `h4xx.io`;
- the legacy signed origins remain only where expected.

### Identity and rooms

- login creates or resolves `@lukasf:h4xx.io`;
- retained rooms contain the current user;
- reviewed rooms grant the current user and canonical bridge bot the intended
  power;
- direct-message titles are participant-derived, not global explicit names;
- the old identity left only rooms that passed the retirement audit;
- old plaintext events are visible where history state permits;
- encrypted events decrypt only where keys were recovered.

### Bridges

- one WhatsApp and one Signal bridge deployment are active;
- each registration matches its deployment and database;
- portal and message mappings exist;
- history/offline-sync queues are understood, not merely empty;
- one inbound and one outbound message works for each bridge;
- attachments render where the source service supplied them;
- no duplicate portals were created during in-place repair.

### Media

- retained-origin MXC requests return objects;
- cache repair reports no missing or conflicting source files;
- local and remote-cache files are hardlinks where expected;
- unresolved encrypted media is tracked separately from missing media.

### GitOps and backups

- Flux reports the Matrix kustomizations ready;
- Synapse and bridge pods are ready without restart loops;
- CNPG backups and WAL archiving are healthy;
- the final source dumps and media manifests remain available;
- all room repair inventories and command outputs are attached to the
  checkpoint record.

## Rollback

Rollback is a cutover decision, not a database reverse rewrite.

1. Stop target write-producing services.
2. Restore ingress and discovery to the unchanged source stack.
3. Restart the source Synapse and canonical source bridges.
4. Verify source login, `/sync`, bridge traffic, and media before reopening
   writes.
5. Preserve the failed target for analysis.
6. If retrying the target, restore its pre-apply CNPG and media checkpoints.
7. Rerun the disposable test with a fresh source dump before another cutover.

Room repair rollback is narrower:

- explicit unsafe room names can be cleared only through the exact-event
  inventory helper;
- account leave operations are not automatically reversible and require a
  supported reinvite/join flow;
- power and history state changes are signed room events and should be changed
  only by emitting a new reviewed state event;
- never delete retained rooms or old bridge database rows during the initial
  rollback window.

## Known Limits and Unsafe Cases

- Matrix does not support an in-place homeserver rename.
- Federated servers continue to know legacy MXIDs and signed event origins.
- Federated event authentication or signatures may remain incompatible after
  a rewrite.
- A retained room with no joined current-domain administrator cannot be safely
  repaired by the provided admin helper.
- A direct room where the replacement user has less power than the retired
  user must remain unresolved until power is repaired through supported APIs.
- Existing populated bridge portals cannot receive arbitrary historical
  batches with standard Synapse.
- WhatsApp and Signal decide how much history and attachment data a linked
  device receives.
- Empty bridge history queues do not prove that all remote history was
  available.
- Missing Megolm keys cannot be reconstructed from the Synapse database or
  media store.
- A retained-origin media cache repair makes bytes reachable but cannot
  decrypt them.
- If history is `shared` yet exact old events still return access errors,
  preserve the room and investigate the denied event's historical state group
  and auth chain. Do not patch database state directly.
- Any room blocked by an audit helper stays on an explicit unresolved list.
  Never weaken the helper's checks to make the batch complete.

## Production Repair Checkpoint: 2026-07-30

This checkpoint records the completed production follow-up without retaining
tokens, recovery keys, private endpoints, room IDs, or message contents:

- exported 1,519 Megolm sessions from an isolated copy of the surviving
  legacy Element profile;
- preserved the replacement account's existing trusted backup and uploaded
  only its 1,502 missing sessions;
- confirmed an idempotent rerun had zero pending sessions;
- confirmed the replacement backup contains 1,526 sessions in total;
- confirmed the representative direct-message room has 203 backed-up
  sessions;
- imported the legacy export into an in-memory Matrix crypto store and
  decrypted 2,227 of 2,297 encrypted timeline events, reaching back to
  2025-02-05;
- confirmed the remaining 70 events use six sessions that were already in the
  replacement account's backup rather than the legacy export;
- retired the legacy account from all 337 reviewed, safe direct-message
  memberships: 79 were already left and 258 were submitted and verified;
- kept one room unresolved because the replacement identity did not yet have
  equal power, as required by the safety guard;
- removed unsafe explicit direct-message titles so clients can derive
  participant-relative names; and
- retained the source stack and all pre-cutover backups pending final user
  acceptance.

The remaining client-side acceptance step is to make the active replacement
device restore or refresh its trusted key backup and verify representative old
messages and attachments. Do not create another backup version merely to force
that refresh.

## Task Record Template

Create one record per migration attempt:

```text
Checkpoint:
Source dump:
Bridge dumps:
Media manifest:
Target CNPG backup:
Scratch namespace:
Source event/media counts:
Target event/media counts:
Authenticated sync result:
Bridge mapping result:
Room repair inventories:
Blocked rooms:
Encrypted-history status:
Cutover start/end:
Rollback deadline:
Operator notes:
```

Do not include access tokens, passwords, recovery keys, private addresses, or
unencrypted secret values in the task record.
