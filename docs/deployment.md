# ATLAS deployment and recovery

This runbook describes the verified deployment path for the ATLAS Compose
runtime and the manual homelab work around it. It is written for an operator
who is new to deploying a Docker web application.

Live host, network, certificate, firewall, DNS, reverse-proxy, and backup facts
must be re-verified before making changes. The examples below use
`atlas.home.arpa`, `/srv/apps/ATLAS`, and `/srv/platform/caddy`; confirm that
those values match the target host.

## How to use this runbook

Commands under **Repository command** are repeatable commands supplied by this
repository. Run them from `/srv/apps/ATLAS` unless another directory is shown.

Steps under **Manual operator action** change the homelab or require knowledge
of its current configuration. Record what was changed and the evidence from
the corresponding verification step before continuing.

## Automated deployment contract

The deployment workflow is deliberately limited to trusted push events:

- A push for `refs/tags/prod` deploys the current commit named by the `prod`
  tag to `/srv/apps/ATLAS`, serving `atlas.home.arpa`.
- A push for `refs/heads/main` manages staging at
  `/srv/apps/ATLAS-staging`, serving `atlas-staging.home.arpa`.
- Pull requests, non-push events, and other branches or tags do not trigger
  this workflow. A deleted `prod` or `main` ref may still enter the job, but
  the automation returns `:ignored` before it mutates the deployment host.

The workflow runs on the dedicated `atlas-deployment` self-hosted runner group
and label. It uses one non-canceling concurrency group for the repository, so a
production or staging host mutation finishes before another one begins. The
workflow grants `contents: write` because the staging path may update a tag;
the existing pull-request and hosted `main` CI remains separate from this
privileged runner.

The workflow checks out source with credentials removed from the checkout,
selects the repository Ruby version, and passes Git authentication only through
the Git child-process configuration used by `bin/deployment-automation`. The
token is not printed, copied into `.env`, or written into Rails secrets. The
workflow provides `GITHUB_BEFORE`, `ATLAS_PRODUCTION_ROOT`, and
`ATLAS_STAGING_ROOT`; host provisioning and runner registration remain owned by
the homelab procedures.

### Production and staging ref behavior

Before a production deployment, the automation verifies that the remote
`refs/tags/prod` still identifies the event revision. A delayed, stale, or
deleted tag event is ignored, and a tag that changes during checkout is refused
before `bin/deploy update` runs.

For a `refs/heads/main` event, the automation reads `refs/tags/staging` and
compares its commit with the event's previous `main` commit:

This is the tracking staging path: staging follows `main` only while its tag
still names the previous `main` commit.

- An absent staging tag remains absent; the event is ignored.
- If staging is intentionally pinned to another revision, it remains pinned and
  the event is ignored.
- If staging is already advanced to the new `main` revision, the event is a safe retry
  and deploys that revision without moving the tag again.
- If staging names the previous `main` revision, the automation advances it
  with `git push --force-with-lease` and verifies the resulting
  `refs/tags/staging` before deploying.

The force-with-lease operation is a compare-and-swap: a concurrent tag change
fails visibly and leaves the staging tag unchanged. Operators can inspect the
failure, resolve the intentional pin or stale event, and retry the workflow.
Staging tag advancement and staging deployment occur in the same workflow run
because a `GITHUB_TOKEN`-created ref update does not recursively trigger an
ordinary push workflow.

Staging tag advancement happens before deployment. If the tag update succeeds
but `bin/deploy update` fails, `refs/tags/staging` may already point at the new
`main` revision after a deployment failure. This is a recoverable state: inspect
the tag, preserve the failed workflow diagnostics, and rerun the failed workflow
for the same `main` revision. Do not move the staging tag again when it already
names that revision; the automation treats the event as a safe retry and runs
`bin/deploy update` without another tag mutation.

For a staging failure, capture the event's `GITHUB_BEFORE` and `GITHUB_SHA`, the
direct and peeled `refs/tags/staging` values, the workflow run URL and result,
the deployment checkout `git rev-parse HEAD` result, the `bin/verify-deployment`
output, and the compare-and-swap result. Redact secrets and bounded diagnostics
from any evidence shared outside the authorized operator records.

Use bounded commands to inspect the state before retrying:

```sh
git ls-remote origin refs/tags/staging refs/tags/staging^{}
git -C "$ATLAS_STAGING_ROOT" rev-parse HEAD
gh run view <workflow-run-id> --json conclusion,headSha,url
gh run rerun <workflow-run-id> --failed
```

Compare the tag and checkout output with `GITHUB_SHA` before rerunning the
failed workflow. The rerun must target that same workflow run; it must not
create another tag movement when staging already names the revision.

Every deployment synchronizes a clean host checkout, preserves the ignored
`.env` and persistent `storage`, checks out the requested revision detached,
then runs `bin/deploy update`, which performs the deployment readiness and
verification checks through `Atlas::Deployment::DeployWorkflow`. The automation
does not run `bin/verify-deployment` a second time. That command remains the
separate operator-facing handoff verifier for manual checks outside the
automated deployment path.

### Operator validation and recovery evidence

For each workflow change or operator rehearsal, record evidence for the exact
`refs/tags/prod` and `refs/heads/main` event cases, unrelated and deleted refs,
stale events, intentional staging pins, duplicate deliveries, compare-and-swap
conflicts, failed deployments, runner outage/restart, and credential rotation.
The repository-side validation commands are:

```sh
RBENV_VERSION=4.0.5 rbenv exec bundle exec rspec spec/deployment
docker compose config --quiet
bin/verify-deployment
docker compose ps
docker compose port atlas 80
git diff --check
```

Run live deployment verification only on the authorized staging-safe host. Do
not treat a local test, a successful tag write, or a healthy runner as proof
that Caddy, DNS, storage, secrets, or the external `web` network are correctly
configured.

## Runtime contract

The production Compose project has one service, `atlas`:

- The image listens on container port 80.
- Compose exposes port 80 to the external Docker network named `web`; it does
  not publish a host port.
- The entrypoint starts as root only long enough to read the file-backed
  secret, then runs Rails and Thruster as UID/GID `1000:1000`.
- The service also joins an internal network for application-local traffic.
- `./storage` is mounted at `/rails/storage`, preserving the primary SQLite
  database and uploaded files across container replacement.
- The service health check requests `/up` with the configured Host header.
- Caddy must be attached to the same external `web` network to proxy to
  `atlas:80`.

The repository deliberately does not configure Caddy, AdGuard Home, UFW, or
Restic. Those are host-level operations and must be handled using the
homelab's existing procedures.

## Prerequisites and host preparation

### Manual operator action: confirm the host

Before changing the host, verify all of the following and record the output:

```sh
hostname
docker version
docker compose version
docker network inspect web
df -h /srv
```

Confirm that Docker Compose is available, that the external `web` network is
the network used by the existing Caddy deployment, and that `/srv` has enough
space for the image, SQLite storage, and backups. If the `web` network does not
exist, stop and follow the approved homelab network procedure; do not create a
second network with a similar name.

### Manual operator action: prepare the application directory

Use the repository's approved checkout process to place the application at
`/srv/apps/ATLAS`. For a first checkout, the resulting directory should be the
repository root:

```sh
sudo install -d -o "$(id -u)" -g "$(id -g)" -m 0755 /srv/apps/ATLAS
cd /srv/apps/ATLAS
git status --short --branch
```

For an existing checkout, inspect the current branch and working tree before
updating it. Preserve local operator files such as `.env` and the `storage`
directory. Use the approved release or shared deployment branch rather than
assuming that `main` is the desired production revision.

The container runs as UID/GID `1000:1000`. Confirm that the application user
can write the storage directory:

```sh
sudo install -d -o 1000 -g 1000 -m 0755 /srv/apps/ATLAS/storage
```

If the existing storage directory contains data, inspect its ownership and
permissions before changing them. Do not remove or replace it as part of
ordinary deployment.

## Rails master key

The Rails master key is supplied to Compose as a file-backed secret. The
recommended `.env` contains only the path to that external file; it must not
contain the key itself.

### Manual operator action: create the external secret

The secret directory and file must be outside the repository, owned by root,
and mode `0600`:

```sh
sudo install -d -o root -g root -m 0700 /srv/platform/secrets/atlas
sudo install -o root -g root -m 0600 /dev/null /srv/platform/secrets/atlas/rails_master_key
```

Place the approved Rails master key into that file using the site's secure
secret-transfer procedure. Do not put the key in a shell command, commit it,
or paste it into `.env`. Recheck the file without printing its contents:

```sh
sudo stat -c '%U:%G %a %n' /srv/platform/secrets/atlas/rails_master_key
sudo test -s /srv/platform/secrets/atlas/rails_master_key
```

### Manual operator action: configure the repository checkout

Create the ignored `.env` from the example and confirm that it contains only
the external secret-file setting:

```sh
cp .env.example .env
grep -n '^RAILS_MASTER_KEY_FILE=' .env
test "$(grep -vE '^(#|RAILS_MASTER_KEY_FILE=|[[:space:]]*$)' .env | wc -l)" -eq 0
```

The expected value is:

```dotenv
RAILS_MASTER_KEY_FILE=/srv/platform/secrets/atlas/rails_master_key
```

Compose mounts that file at `/run/secrets/rails_master_key`. The root bootstrap
reads the mounted file, exports `RAILS_MASTER_KEY` only to the application
process, and then drops that process to UID/GID `1000:1000`. Keep the host file
root-owned and mode `0600`; do not weaken its permissions to accommodate the
non-root application process.

## First deployment

### Repository command: validate and deploy

Run the complete first deployment from the repository root:

```sh
docker compose config --quiet
bin/deploy fresh
bin/verify-deployment
```

`bin/deploy fresh` validates the Compose file, builds the `atlas` image, starts
the service, runs `db:prepare`, runs `db:seed`, and verifies the running
service. `db:prepare` creates or migrates the primary SQLite database in the
persisted storage volume. Seeding creates the `index` Manual landing page when
needed.

If the first command fails, do not continue to `up`. Resolve the Compose
configuration or secret-file problem first. If the deployment command fails,
inspect the command output and service logs without printing secret contents:

```sh
docker compose ps
docker compose logs --no-color --tail=200 atlas
```

### Repository command: verify the handoff

The verifier checks Compose configuration, service health, the absence of a
published host port, `/up`, `/status`, and secret hygiene:

```sh
bin/verify-deployment
docker compose ps
docker compose port atlas 80
```

The final command should produce no published host port. An empty result is
expected because Caddy reaches the service over the external `web` network.

## Routine update, restart, and seed operations

### Repository command: update the application

After checking out the approved application revision, run:

```sh
bin/deploy update
```

This validates the Compose file, builds the image, replaces the service, runs
database preparation and seeding, verifies the endpoints and secret handling,
and checks that the existing Manual landing-page marker did not unexpectedly
change.

### Repository command: restart without rebuilding

For a service restart that should preserve application data:

```sh
bin/deploy restart
```

The workflow records a landing-page and database-storage marker before the
restart and compares both after verification. It then waits for the Compose
healthcheck to report the `atlas` container running and healthy before it
probes HTTPS. This avoids treating the short Rails/Puma startup window, or a
transient reverse-proxy `502`, as a failed deployment.

The readiness waiter polls every 2 seconds and has a 120-second deadline by
default. These values are configurable through the deployment workflow's
construction seam for automated callers; the normal `bin/deploy restart`
command uses the defaults. The wait is health-based rather than an
unconditional fixed sleep. If the container becomes unhealthy, exits, or does
not become ready before the deadline, the command stops before HTTPS
verification and reports bounded, redacted status, health, command-error, and
recent-log diagnostics.

For local operator inspection after a readiness failure, use the same bounded
Compose views without copying their output into tickets or chat:

```sh
docker compose ps --format json --all atlas
docker compose logs --no-color --tail=200 atlas
```

Treat raw container output as sensitive even though deployment failure messages
redact known secret values. Do not print or paste the Rails master key, secret
files, credential-like values, or unrestricted logs. An unexpected persistence
marker change is also a deployment failure; stop and investigate the storage
mount and database before retrying.

### Repository command: prepare and seed explicitly

Use this when the application needs the database setup or seed operation
without a new image build:

```sh
bin/deploy seed
```

The command runs `db:prepare`, then `db:seed`, and verifies the service.

## Caddy and LAN access

### Manual operator action: inspect the existing Caddy setup

Before changing Caddy, inspect its actual configuration location, container or
service name, Docker networks, and reload procedure. The expected integration
is a reverse proxy from the ATLAS hostname to the Compose service over the
external `web` network. A minimal conceptual route is:

```caddyfile
atlas.home.arpa {
    reverse_proxy atlas:80
}
```

Treat this as a reference, not a drop-in replacement. Apply the site's existing
Caddy formatting, storage, and reload conventions under `/srv/platform/caddy`.
Do not modify Caddy as part of an application repository deployment unless the
operator has separately approved that host change.

After a manual edit, validate and reload Caddy using the installed deployment's
documented commands. Capture the validation and reload output. Confirm that
the Caddy process is attached to `web` and can resolve `atlas`:

```sh
docker network inspect web
```

### Manual operator action: configure private DNS

In AdGuard Home, verify the existing LAN DNS policy and add or update the
private record for `atlas.home.arpa` to the homeserver's LAN address. Do not
create a public DNS record or expose the service to the public internet.

From a LAN client, verify the answer against the intended DNS server:

```sh
dig +short atlas.home.arpa @<LAN_DNS_ADDRESS>
```

The result must be the homeserver's private address. Re-verify the address if
the homeserver uses DHCP or a changed reservation.

### Manual operator action: verify certificate, proxy, and firewall

From a LAN client, verify the complete HTTPS path and the two application
endpoints:

```sh
curl --fail --silent --show-error --location https://atlas.home.arpa/up
curl --fail --silent --show-error --location https://atlas.home.arpa/status
openssl s_client -connect atlas.home.arpa:443 -servername atlas.home.arpa </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Confirm that the certificate subject/SAN and validity dates are correct, Caddy
routes to ATLAS, and the response is coming through HTTPS. On the host, inspect
listeners and the approved firewall policy:

```sh
ss -ltnp
sudo ufw status verbose
```

The ATLAS Compose service must not add a host port. Verify that only the
intended LAN-facing proxy path is allowed by the host firewall. Re-check the
actual LAN client, VLAN, and firewall policy before declaring the service
LAN-only.


### Copy certs to clients on the LAN

First transfer the certificate from the homeserver:

```
scp sam@<HOMESERVER_LAN_ADDRESS>:/srv/apps/ATLAS/.codex-tmp/caddy-local-root.crt .
```

Verify its SHA-256 fingerprint matches the homeserver before trusting it:

```
openssl x509 -in caddy-local-root.crt \
  -noout -subject -issuer -fingerprint -sha256
```

Then install it according to the laptop’s OS.

##### Windows

1. Double-click caddy-local-root.crt.
1. Select Install Certificate.
1. Choose Current User or Local Machine.
1. Select Place all certificates in the following store.
1. Choose Trusted Root Certification Authorities.
1. Finish the wizard and restart Chrome, Edge, or Firefox.

Microsoft’s trusted root store is the correct location for private CA certificates. Microsoft documentation

##### macOS

1. Open Keychain Access.
1. Select the System keychain.
1. Drag caddy-local-root.crt into it.
1. Double-click the imported certificate.
1. Expand Trust and set When using this certificate to Always Trust.
1. Close and restart the browser.

[Apple’s Keychain documentation](https://support.apple.com/en-ca/guide/keychain-access/kyca2431/mac)

## Production rollback and recovery

The authoritative production recovery path is a revert commit followed by moving
the `prod` tag forward. It keeps the normal reviewed source and deployment path
in use; the `bin/deploy rollback` helper is not the primary recovery mechanism.

### Repository command: revert the faulty change

From a clean clone on `main`, with the faulty production change identified:

```sh
git switch main
git revert <faulty-commit>
git push origin HEAD:main
```

After the revert commit passes the normal checks, move `prod` to that commit.
First confirm that the remote `prod` ref still identifies the faulty production
revision. Use the exact direct-ref object ID returned by this check as
`<current-prod-ref>`; for an annotated tag, compare the peeled ID with
`<faulty-commit>` and use the tag object's direct-ref ID for the lease:

```sh
git ls-remote origin refs/tags/prod refs/tags/prod^{}
```

Then move the tag with a compare-and-swap lease. The tag movement selects the
production workflow, which verifies the tagged revision and updates
`/srv/apps/ATLAS`:

```sh
git push --force-with-lease=refs/tags/prod:<current-prod-ref> origin <revert-commit>:refs/tags/prod
```

After the workflow reports completion, run verification on the authorized
deployment host from `/srv/apps/ATLAS`:

```sh
bin/verify-deployment
```

Do not force a tag over an unrelated production revision or use an image-only
rollback to bypass source review. If the tag movement, deployment, or
verification fails, preserve the bounded workflow diagnostics and follow the
operator recovery order below. A later revert commit and another guarded
forward `prod` tag movement are the supported retry path.

## Backup, restore, and recovery

### Manual operator action: verify backup coverage

Before relying on a backup, verify the existing Restic repository, schedule,
retention policy, repository password/key availability, and storage location.
Confirm that backups cover at least:

- `/srv/apps/ATLAS/storage`, including the primary SQLite database and uploads;
- the checked-out deployment configuration and `.env` path (never the master
  key contents in an unsafe location); and
- the relevant Caddy and DNS configuration under `/srv/platform/caddy` and the
  site's AdGuard backup procedure.

Use the site's approved Restic environment rather than copying secrets into a
command line. Capture representative evidence that a recent snapshot exists
and that a test file or staging restore can be read. A snapshot listing alone
does not prove that the SQLite database or Caddy configuration can be restored.
Keep an encrypted, access-controlled offsite copy of the Rails master key and
the Restic recovery credentials. The local backup disk does not provide
whole-host protection and must not be the only place those recovery inputs are
preserved.

### Manual operator action: restore application storage

Automated restore is intentionally not provided. For a local restore, stop
application traffic, verify the source, stage the restored files, and swap the
storage directory only after the staged copy is complete. This preserves the
pre-restore directory so the operation can be reversed if verification fails.

Set the source to a directory whose contents are the contents of the mounted
`storage` directory, not a directory containing another nested `storage`
directory:

```sh
storage_path=/srv/apps/ATLAS/storage
restore_source=/srv/restore/atlas/storage
restore_id=$(date -u +%Y%m%dT%H%M%SZ)
restore_stage=/srv/apps/ATLAS/storage.restore-${restore_id}
restore_previous=/srv/apps/ATLAS/storage.previous-${restore_id}

test -d "$restore_source"
sudo test -f "$restore_source/production.sqlite3"
sudo test -r "$restore_source/production.sqlite3"
docker compose stop atlas
sudo install -d -o 1000 -g 1000 -m 0755 "$restore_stage"
sudo cp -a "$restore_source/." "$restore_stage/"
sudo chown -R 1000:1000 "$restore_stage"
sudo find "$restore_stage" -type d -exec chmod u+rwx {} +
sudo find "$restore_stage" -type f -exec chmod u+rw {} +
sudo mv "$storage_path" "$restore_previous"
sudo mv "$restore_stage" "$storage_path"
sudo chown -R 1000:1000 "$storage_path"
```

If any source check or copy fails, stop before the `mv` commands. Do not remove
`$restore_previous` until the restored service has passed health and persistence
checks. Confirm the resulting path and primary database ownership without
printing secret contents:

```sh
sudo test -f "$storage_path/production.sqlite3"
sudo stat -c '%U:%G %a %n' "$storage_path" "$storage_path/production.sqlite3"
```

Record the restored persistence marker, restart the service, verify the marker
is unchanged, and run the deployment verifier:

```sh
storage_marker() {
  docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails runner \
    'require "digest"; page = ManualPage.find_by!(slug: "index"); database = ActiveRecord::Base.connection_db_config.database; puts [page.id, page.created_at.iso8601(6), Digest::SHA256.hexdigest(page.content), Digest::SHA256.file(database).hexdigest].join(" ")'
}

docker compose up --detach --no-build atlas
bin/verify-deployment
after_restore_marker=$(storage_marker)
docker compose restart atlas
after_restart_marker=$(storage_marker)
test "$after_restore_marker" = "$after_restart_marker"
```

The storage swap is recoverable: if verification fails, stop the service, move
the failed `$storage_path` aside, move `$restore_previous` back to
`$storage_path`, restore ownership `1000:1000`, and restart before retrying.

A local storage restore cannot recover a destroyed host, Docker installation,
external `web` network, Caddy configuration, AdGuard records, firewall rules,
or the Rails master key unless those items were separately preserved. Whole-
host recovery therefore requires the host rebuild procedure, the repository
revision, the external secret, the Compose network, the reverse-proxy and DNS
configuration, and a verified Restic restore.

### Manual operator action: recovery order

For a host-level incident, use this order and record evidence at each handoff:

1. Re-provision the host and Docker/Compose versions according to the approved
   homelab procedure.
2. Restore or recreate the root-owned Rails master-key file at the configured
   external path without exposing its contents.
3. Restore `/srv/apps/ATLAS`, its `storage` data, and the intended application
   revision.
4. Recreate or verify the external `web` network and the storage ownership for
   UID/GID `1000:1000`.
5. Restore and validate Caddy, AdGuard DNS, and firewall configuration through
   their separate procedures.
6. Run `docker compose config --quiet`, then `bin/deploy fresh` only when the
   restored storage state and migration plan are understood.
7. Run `bin/verify-deployment` and the HTTPS, LAN, certificate, proxy, and
   backup checks above.

If the database is corrupt, the master key is unavailable, or a migration has
already changed the schema, stop before running `db:prepare` again and involve
the service owner. Do not treat a container rebuild as a database recovery.

## homelab-manual ownership and reconstruction

Host-level provisioning and recovery remain owned by the
[`homelab-manual`](https://github.com/segfaultsoftware/homelab-manual)
repository. The ATLAS-side contract is intentionally limited to application
paths, workflow behavior, verification seams, and links to the host procedures.

The dependency owners are homelab-manual #6, homelab-manual #7, and
homelab-manual #8, in that order.

- homelab-manual [#6](https://github.com/segfaultsoftware/homelab-manual/issues/6)
  is the owner of runner provisioning, security, identity, lifecycle, cleanup, and
  credential handling. It is the first owner in the reconstruction sequence.
- homelab-manual [#7](https://github.com/segfaultsoftware/homelab-manual/issues/7)
  is the owner of ATLAS host integration, checkout prerequisites, Docker access, storage,
  the external `web` network, and Caddy-facing host integration. #7 depends on
  #6 and is the second owner in the reconstruction sequence.
- homelab-manual [#8](https://github.com/segfaultsoftware/homelab-manual/issues/8)
  is the owner of operations, recovery, maintenance, and clean reconstruction evidence.
  #8 depends on #7 and is the third owner in the reconstruction sequence.

Follow #6 before #7 before #8, then use this runbook to validate the
application-facing workflow contract. Do not put runner registration tokens,
private keys, Rails secrets, or unneeded host addresses in this repository or
in the linked tickets. Re-check the links and their completion evidence when
the deployment system changes so the two repositories cannot silently drift.

## Local authentication rollout

ATLAS uses local email/password accounts through Devise. The migration
`20260809000100_remove_google_oauth_and_reset_users.rb` is a one-time,
irreversible destructive reset for the local-authentication rollout. It deletes
Profiles before Users, removes the remaining OAuth identity columns, and does
not migrate existing OAuth accounts.

Before deploying this revision, confirm a verified backup and an approved
maintenance window. Run the migration through the normal deployment command:

```sh
bin/deploy update
```

The migration must run against the intended disposable or approved deployment
database only after the data-discard implications have been reviewed. Do not
run it against production data without the application's approved destructive
rollout procedure. Existing users and profiles will be removed; users must
register again after the reset. The migration is irreversible, so rollback
requires restoring a verified database backup rather than running
`db:rollback`. There is no OAuth account migration or password-recovery feature
in this rollout.

This runbook still does not configure public exposure, general-purpose secret
management, Caddy files, AdGuard Home, UFW, or Restic configuration.

## Documentation validation

Before committing a runbook change, perform the repository-side checks below
and review all manual examples against the current host procedures:

```sh
docker compose config --quiet
git diff --check
```

Review Markdown links and command examples, walk through the Compose
configuration, and perform the manual Caddy, AdGuard, certificate/proxy,
LAN-only, and representative Restic restore checks on the target homelab
before relying on the deployment.
