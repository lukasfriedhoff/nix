# Media Stack Linking and Download Promotion

This document describes the GitOps implementation used to:

1. keep Jellyseerr/Jellyfin wiring configurable per cluster, and
2. automatically promote imported qBittorrent downloads to a "next stage" path after a retention period.

## Scope

- Apps repo: `flux-apps/apps/media`
- Cluster config repo: `flux-cluster/base/base-config.yaml` and overlays
- Initial rollout target: `homelab-testing` (`testing-srv3`)

## What “linking instances” means here

Jellyfin and Jellyseerr do not support true active-active clustering between separate Kubernetes clusters.
Instead, this setup uses **configurable instance wiring** so each cluster can point to the intended media endpoints without hardcoded domains.

The following variables are now first-class in media app config:

- `jellyseerr_app_url`
- `jellyfin_server_name`
- `jellyfin_internal_base_url`
- `jellyfin_external_hostname`
- `jellyfin_forgot_password_url`
- `media_auth_issuer_url`
- `radarr_external_url`
- `sonarr_external_url`

## Automatic “next stage” promotion

A new CronJob (`qbittorrent-download-promoter`) runs in namespace `media`.

Behavior:

- reads completed torrents from qBittorrent API
- filters by imported categories (default: `radarr/sonarr/lidarr/readarr-imported`)
- waits until torrent age exceeds `media_download_promotion_min_age_hours`
- moves torrent data location to `${media_download_promotion_target_base}` buckets:
  - `radarr-imported -> /media/staged/movies`
  - `sonarr-imported -> /media/staged/tv`
  - `lidarr-imported -> /media/staged/music`
  - `readarr-imported -> /media/staged/books`

This is done using qBittorrent Web API `torrents/setLocation` (GitOps-controlled, no manual drift).

## New variables

In `base-config`:

- `media_download_promotion_enabled` (`disabled|enabled`)
- `media_download_promotion_dry_run` (`true|false`)
- `media_download_promotion_cron`
- `media_download_promotion_min_age_hours`
- `media_download_promotion_category_regex`
- `media_download_promotion_target_base`

Testing overlay currently enables promotion with:

- `media_download_promotion_enabled: "enabled"`
- `media_download_promotion_dry_run: "false"`
- `media_download_promotion_cron: "15 */6 * * *"`
- `media_download_promotion_min_age_hours: "120"`
- `media_download_promotion_target_base: "/media/staged"`

## Rollout commands (testing)

```bash
# 1) Push flux-apps changes
cd ~/git/lukasfriedhoff/flux-apps
git add apps/media examples/apps/media
git commit -m "feat(media): add configurable linking and download promotion cronjob"
git push

# 2) Push flux-cluster values/overlay
cd ~/git/lukasfriedhoff/flux-cluster
git add base/base-config.yaml overlays/testing-srv3/cluster-patch.yaml
git commit -m "feat(testing): enable media download promotion policy"
git push

# 3) Reconcile on testing cluster
flux --context=homelab-testing -n flux-system reconcile source git flux-apps
flux --context=homelab-testing -n flux-system reconcile source git flux-cluster
flux --context=homelab-testing -n flux-system reconcile kustomization media-app --with-source
flux --context=homelab-testing get kustomizations -A
```

## Validation commands

```bash
# Verify CronJob exists
kubectl --context=homelab-testing -n media get cronjob qbittorrent-download-promoter

# Trigger one manual run
kubectl --context=homelab-testing -n media create job --from=cronjob/qbittorrent-download-promoter qbittorrent-download-promoter-manual

# Inspect logs
kubectl --context=homelab-testing -n media logs job/qbittorrent-download-promoter-manual

# Check qBittorrent and staged path
kubectl --context=homelab-testing -n media get pod -l app.kubernetes.io/instance=qbittorrent
```

## Rollback

To disable without deleting resources:

- set `media_download_promotion_enabled: "disabled"` in overlay/base and reconcile.

