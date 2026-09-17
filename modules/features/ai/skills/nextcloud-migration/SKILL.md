---
name: nextcloud-migration
description: Migrate/merge a docker (or other) Nextcloud into a k8s Nextcloud — files rsync, password-hash portability, files:scan, OIDC-UUID mapping, declarative app seeding. Use when consolidating Nextcloud instances or moving one into the FluxCD k8s stack.
---

# Nextcloud migration (docker → k8s, merge-into-prod)

Field-tested merging the docker-host instance (`nextcloud.h4.ddnss.org`,
NC31/MariaDB, 27 users) into prod k8s Nextcloud (NC34/CNPG-PG) — 2026-09-13.

## What is and isn't portable

- **DB-level import across a major/engine gap is NOT possible.** NC31→NC34 +
  MySQL→Postgres = schema + engine + PK conflicts. The supported merge is:
  **files rsync + recreate users + copy password hashes + `occ files:scan` +
  rebuild shares** — NOT a mysqldump→psql.
- **Password hashes ARE portable** — `oc_users.password` is self-contained
  (`3|$argon2id…`, `1|$2y$…` bcrypt). Copy the hash string into the target
  `oc_users.password` and the old password works. (Only pre-2015 legacy hashes
  depend on `passwordsalt`.)
- **App passwords / TOTP are instance-`secret`-bound** — they only survive if
  you carry the old `secret`+`passwordsalt`+`instanceid` (a *move*, not a
  *merge*). In a merge they cannot be carried; users re-pair devices.
- **Shares don't lift 1:1** — after `files:scan` the target file IDs differ,
  so `oc_share` rows can't be copied; rebuild by (owner, path, share-target)
  via `occ` scripting.
- **Check `occ encryption:status` first** — server-side encryption ON means
  you must `encryption:decrypt-all` before a plain rsync means anything.

## The OIDC-UUID trap (the big one)

If the target uses **oidc_login**, its usernames are the OIDC **subject UUIDs**
(e.g. `08f11a25-…`), not friendly uids. A source user `bj` has no target UUID
until they log in via OIDC once (or you provision them in the IdP —
authelia/LLDAP — with a known sub). **Do not mint accounts blindly** — wrong
identity for real users. Resolve uid→UUID before provisioning; copy source
data to **staging** (`/data/_import_ddnss/<uid>/`) until the UUID is known,
then `mv` into `<UUID>/files/` (same volume = instant) + `files:scan`.

## Transfer: the migration pod

RWX data PVC (Nextcloud data is RWX) → mount it in a second pod alongside the
live app. **Pin the pod to the node that hosts the volume's Longhorn replicas**
(I/O stays local). Ephemeral SSH key → source; `kubectl cp` the scripts in
(heredoc-over-exec gets SIGTERM'd on long execs). Launch detached with
`setsid`.

```
kubectl -n <ns> exec <pod> -- setsid sh -c 'sh /root/migrate.sh >/dev/null 2>&1 &'
```

**Throughput lesson:** Nextcloud data = huge counts of small files. A single
rsync stream to Longhorn **RWX-over-NFS is latency-bound at ~6 MiB/s** (per-file
create+fsync round-trips) regardless of `--bwlimit`. **tar streaming does NOT
fix it** (still per-file NFS ops) and loses resumability. The lever is
**parallelism** — run N resumable streams (`xargs -P 3`, one per user), each
`rsync -aH --numeric-ids --chown=33:33 --inplace --partial --whole-file
--bwlimit=<per-stream>`. `--inplace --partial` = safe resume; re-run the driver
to continue. Keep per-stream bwlimit modest — you're writing into the **live**
volume the app serves, so bulk writes degrade it for current users (see the
longhorn skill: RWX = one share-manager, all clients funnel through it).

Gotcha: `pkill`-ing processes inside a container can wedge its namespace
(`runc … setns … ns/ipc: No such file`); if exec starts failing, delete +
recreate the pod (data on the PVC persists).

## Declarative app seeding (zero-downtime)

Prod runs `appstoreenabled=false` and seeds third-party apps via the
`seed-custom-apps` initContainer (`fetch_app <name> <url> <sha256> <marker>
<version>`) + enables them in the postStart (`enable_custom_app_if_present
<app> <marker>`). To add apps migrated from the source: pin each to its
**NC-target-compatible** appstore release (URL+sha256+version), add a
`fetch_app` + an `enable_custom_app_if_present` line, commit. The initContainer
change rolls the deployment; with the configured surge strategy an old pod
serves throughout (zero downtime). sha256 guards integrity, so
`<name>/appinfo/info.xml` is a fine universal extraction marker.

## Order of operations

1. Add apps declaratively (safe, reversible) — do this first.
2. Size the target data PVC to source `du` + growth; confirm free space.
3. `encryption:status` off; capture source inventory (`occ user:list`, per-dir
   `du`, `oc_share`/`oc_group_folders` counts).
4. Bulk copy → staging (parallel, resumable) — the long pole; runs for
   hours/days into the live volume.
5. Resolve uid→UUID mapping (IdP work) — the gate for everything below.
6. Per user: create/confirm account → `mv` staged files into `<UUID>/files/`
   → `chown 33:33` → `files:scan --path` → copy password hash → rebuild shares.
7. Cleanup: delete migration pod + key secret; shred local key; **remove the
   migration pubkey from the source's authorized_keys**.

## Complete-DB move (convert-type) — when you must preserve EVERYTHING

A files+hashes merge loses DB-resident data (Passwords-app vault, calendars,
contacts, shares, deck, versions) and secret-bound data. To keep it all, do a
**complete DB move**: `occ db:convert-type` MySQL→Postgres + `occ upgrade`
across every major, then REPLACE the target DB (you cannot UNION two Nextcloud
DBs — every table has its own PK space). Rehearse in a throwaway stack first.

Two non-obvious gotchas that silently destroy data — both cost a rehearsal:
- **`db:convert-type` needs each app's CODE present to convert its tables.** It
  builds tables from the app's schema definition. Run it with the source's
  `custom_apps/` mounted, or third-party tables (incl. the passwords vault) are
  **silently dropped** — the target just has fewer tables, no error. (Calendars/
  contacts survive regardless — bundled `dav`.)
- **FK-using apps break the alphabetical copy order.** `news`
  (`oc_news_feeds.folder_id → oc_news_folders`) aborts the whole convert with a
  Postgres FK violation (feeds copied before folders). Empty/reorder those
  tables first. Verify the final table count matches the source dump.

Other: password hashes verify fine with a placeholder instance secret (argon2id
is self-contained) — but the **Passwords-app vault is encrypted with the
instance `secret`**, so the target must adopt the SOURCE's `secret` for it to
decrypt. `--routines`/`--triggers` on mysqldump silently yield 0 bytes if the
DB user lacks the privilege (Nextcloud uses neither). Streaming a big gzip
through `kubectl exec -i` corrupts it — dump to a file, rsync it in.
