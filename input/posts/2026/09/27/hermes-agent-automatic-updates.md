Title: How to correctly perform automatic updates for Hermes agent
published: 2026-09-27
tags:
- articles
announce: fedi
Lead: Updating Hermes agent on an automatic schedule is much, much harder than it should be.
---
As someone who has used Hermes Agent for several months now, one of the biggest struggles is just keeping it updated, keeping it working through updates, and adapting the plugins I maintain to the frequent codebase changes.

A reasonable app, of course, would have a design that can account for scheduled automatic updates, and apply them regularly. But Hermes is a giant, sprawling codebase, and does not.  As of writing, you can't even pin Hermes to any particular release; updating means pulling the most recent code from GitHub. The recent redesign as of last week has made this even worse, as Hermes has created an automatic package manager of its own called Hermes pm, and overcomplicated and over-engineered uv environment management. As a side-effect of these changes, cron jobs inside the agent no longer run at all, and running Hermes update will destroy your systemctl units. Even if you wrote them by hand, yourself. In order to keep Hermes working, not only do you need to update from upstream, you also need to apply whatever patches your local environment needs to keep it running, account for the fact that systemctl units will be broken, and track the status of secondary services like the Hermes dashboard yourself.

Unfortunately, every environment is slightly different. The following are not downloadable scripts that will work for you, but rather examples showing and explaining what needs to happen. If you are using Debian or a distribution of Linux based on it, this recipe will need seasoning to taste. If you are using some other OS, or not using systemctl, you will need to start from these ingredients and build your own thing for your particular environment. These are scripts written over time, for my system, with learnings over months. I have tried to make them generic, but it's certain I missed some hard-coded paths that are different on your system, or assumed tools you do not have installed. You should read over the entirety of all scripts and make all required changes before using them yourself. 

Note that I am also assuming you understand the security implications of running Hermes at all, and applying updates to it. Hermes should always be running on a physical machine of its own, on a separate vlan from all of your other devices, with no access to your internal network, and a default-deny policy for both incoming and outgoing connections set at the firewall level. Do not trust Hermes internal security, and decide for yourself what holes you need to punch in your security policy in order to make Hermes useful to you. I personally have many, but each one was an intentional decision that I made.

## Patch Tracking ##

Unfortunately, you won't get away with running Hermes Agent for long, without needing to apply multiple environment-specific patches. This could be because of a quirk of your environment that Hermes does not account for, or because of a pull request that fixes a bug that's critical for you and may take weeks or months to merge. Hermes tries to do this with git stash. Unfortunately, that makes your local changes impossible to account for and track, and leaves you in a situation where they can be overwritten without warning.  Before patching Hermes directly, you need to:
* subscribe to any PR that contains the feature or fix you need, so you'll be notified when it's merged, and you can delete your patch
* follow any changes on GitHub to any file/submodule you're patching, so you'll know when your patch will stop working and you need to modify it or remove it

Then, when you need to change Hermes, create a folder called something like `~/.Hermes/patches` and save your patch as a diff there. 

### patching cron ###

As of writing, this is a patch you will require to get cron working again after update. Save it as something like `~/.Hermes/patches/cron-worker-env-pin.patch` so it can be applied automatically later:
``` diff
diff --git a/cron/scheduler_worker_env.py b/cron/scheduler_worker_env.py
index ef13355fca..60fe3d1dd2 100644
--- a/cron/scheduler_worker_env.py
+++ b/cron/scheduler_worker_env.py
@@ -27,6 +27,30 @@ def _installed_purelib() -> Path | None:
         return None
 
 
+def _committed_venv_site_packages(repo_root: Path) -> Path | None:
+    """Site-packages of the PM-committed dependency venv for this checkout, if any.
+
+    The worker child never runs ``hermes_bootstrap`` (it is spawned as
+    ``sys.executable -m cron.scheduler``), so ``pm.environments.activate_dependencies``
+    never runs in it. The shared subprocess sanitizer strips the gateway's own
+    PYTHONPATH — including the committed site-packages — because user children must
+    not see our tree; this child IS Hermes, so the dependency path must be re-pinned
+    here or every worker dies at ``import ruamel`` (hermes_yaml → ruamel.yaml).
+    """
+    try:
+        from pm.environments import committed_venv, site_packages
+    except Exception:
+        return None
+    try:
+        env = committed_venv(repo_root)
+        if env is None:
+            return None
+        sp = site_packages(env)
+        return sp if sp.is_dir() else None
+    except Exception:
+        return None
+
+
 def pin_hermes_tree_on_pythonpath(worker_env: dict, repo_root: Path) -> dict:
     """Prepend ``repo_root`` to the worker env's own PYTHONPATH (never ``os.environ``'s).
 
@@ -37,6 +61,10 @@ def pin_hermes_tree_on_pythonpath(worker_env: dict, repo_root: Path) -> dict:
     root = str(repo_root)
     if _installed_purelib() == Path(root).resolve():
         return worker_env
+    pins = [root]
+    committed = _committed_venv_site_packages(repo_root)
+    if committed is not None:
+        pins.append(str(committed))
     existing = [e for e in worker_env.get("PYTHONPATH", "").split(os.pathsep) if e]
-    worker_env["PYTHONPATH"] = os.pathsep.join(dict.fromkeys([root, *existing]))
+    worker_env["PYTHONPATH"] = os.pathsep.join(dict.fromkeys([*pins, *existing]))
     return worker_env
```

### applying patches ###

Next, you need a script that can be called after an update happens, to apply your patches. It might look something like this, saved in `~/.Hermes/scripts/apply-host-patches.sh` or where ever you keep the scripts that Hermes is allowed to run. In this script, you will need to modify the paths at the top to point to your Hermes checkout, and the place you keep your patches. You will also need to add a line here every time you need to create a patch. When you don't need a patch anymore, delete the patch, and remove the line from this script:
``` bash
#!/usr/bin/env bash
# Re-apply the standing host-tree patches to the Hermes checkout.
#
# `hermes update` clobbers uncommitted host-tree edits; this re-applies the
# sanctioned local-only patches afterwards. Patch files live in
# ~/.hermes/patches/ as real unified diffs (regenerate with:
#   cd ~/.hermes/hermes-agent && git --no-pager diff --output=~/.hermes/patches/<name>.patch -- <file>
# NEVER regenerate via shell redirection — a pipe compactor mangles the bytes).
#
# Idempotent: already-applied patches are detected by their marker symbol and
# skipped. Fails loudly (exit 1) when a patch cannot be applied — after heavy
# upstream drift a manual port may be needed, and pretending otherwise is how
# a server silently dies at boot.
set -uo pipefail

REPO=/home/fastfinge/.hermes/hermes-agent
PATCHES=/home/fastfinge/.hermes/patches
FAILED=0

apply_patch() {
    local patch="$1" file="$2" marker="$3"
    if grep -qF "$marker" "$REPO/$file"; then
        echo "already present: $(basename "$patch")"
        return 0
    fi
    if command git -C "$REPO" --no-pager apply --3way "$patch" 2>/dev/null \
        || command git -C "$REPO" --no-pager apply "$patch" 2>/dev/null; then
        if grep -qF "$marker" "$REPO/$file"; then
            echo "applied: $(basename "$patch")"
            return 0
        fi
    fi
    echo "FAILED to apply $(basename "$patch") to $file — marker '$marker' missing; manual port needed (git apply --reject to inspect)." >&2
    FAILED=1
    return 1
}

apply_patch "$PATCHES/cron-worker-env-pin.patch" "cron/scheduler_worker_env.py"     "_committed_venv_site_packages"

if [[ "$FAILED" -ne 0 ]]; then
    echo "Host patches INCOMPLETE. fleet is on updated code without all host patches; manual port needed."
    exit 1
fi
echo "Host patches OK."
```

## Automatic Updating ##

Now that you have an infrastructure for patching Hermes in place, and a working cron again, it's time to create the script that will perform your nightly update. Once again, you will, at absolute minimum, need to modify the paths at the top. Save it somewhere like `~/.hermes/scripts/nightly-hermes-update.sh` or where ever you keep the scripts you let Hermes run. This script is commented to explain what we're doing, in what order, and why. Once you have it modified to taste, you will need to add it as a no-agent cron job inside Hermes.

### The Script ###

``` bash
#!/usr/bin/env bash
# Nightly Hermes update pipeline — updates are MANDATORY for security.
#
# Runs in this order (Hermes core 4th, because `hermes update` restarts):
#   1. hermes plugins update   (git-sourced plugins, one by one, isolated)
#   2. hermes skills update
#   3. uv sync pre-sync        (stale-venv guard)
#   4. hermes update --yes     (restarts the gateway internally)
#   5. host-patch re-apply + fleet restart + unit sanity — ONLY on step-4 success
set -uo pipefail
# change all of these, at least:
REPO=/home/fastfinge/.hermes/hermes-agent
HERMES="$REPO/.hermes/bin/hermes"          # pinned checkout entry
PATCH_SCRIPT=/home/fastfinge/.hermes/scripts/apply-host-patches.sh
UNIT_DIR=/home/fastfinge/.config/systemd/user
EXPECTED_LAUNCHER="$REPO/.hermes/bin/hermes"

# Self-exec into a transient systemd scope to escape the gateway's cgroup.
#
# This script is a no_agent cron job — it runs as a child of the gateway
# process, inside the gateway's systemd cgroup (KillMode=mixed). When
# `hermes update` drains and restarts the gateway, systemd sends SIGTERM to
# the entire cgroup, killing this script and the update subprocess before it
# can call `reset-failed` + `start`. The gateway exits 75 (TEMPFAIL), nothing
# restarts it, and Hermes stays offline until you manually `hermes gateway
# restart`.
#
# Re-execing via `systemd-run --user --scope --collect --quiet` puts this
# script in its own cgroup (`run-<id>.scope`), outside the gateway's. The
# update and this script both survive the gateway's death and complete the
# restart sequence. The guard checks the cgroup name so we only re-exec once.
if [[ -z "${NIGHTLY_UPDATE_REEXECED:-}" ]]; then
    if _CGROUP="$(cat /proc/self/cgroup 2>/dev/null)" && echo "$_CGROUP" | grep -q "hermes-gateway"; then
        if command -v systemd-run >/dev/null 2>&1; then
            export NIGHTLY_UPDATE_REEXECED=1
            exec systemd-run --user --scope --collect --quiet -- "${BASH_SOURCE[0]}" "$@"
        fi
    fi
    unset _CGROUP
fi

REPORT=""
FAILED=""

run_step() {
    local label="$1"
    shift
    local out
    local rc
    out="$("$@" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        FAILED+="${label} FAILED (exit ${rc}):"$'\n'"${out}"$'\n\n'
        return 1
    fi
    # Heuristic: if the output mentions an actual change, surface it.
    # Filter out boring "already up to date" / "no updates" / "nothing to do" noise.
    if echo "$out" | grep -qiE 'updated|installed|upgraded|new version|changed|pulling|fetched'; then
        if ! echo "$out" | grep -qiE 'already up.?to.?date|no updates|nothing to (do|update)|no changes'; then
            REPORT+="${label}:"$'\n'"${out}"$'\n\n'
        fi
    fi
    return 0
}

# 0. Boot probe. If the pinned launcher itself cannot run, abort before ANY step.
BOOT_OUT="$("$HERMES" --version 2>&1)"
BOOT_RC=$?
if [[ $BOOT_RC -ne 0 ]] || echo "$BOOT_OUT" | grep -qi "no dependency environment is committed"; then
    echo "Nightly update ABORTED before touching anything: pinned launcher not bootable (exit ${BOOT_RC})."
    echo
    echo "$BOOT_OUT"
    exit 1
fi

# 0b. Plugin-workspace hygiene: pm/workspace.py excludes uv.lock from env
#     workspace copies, but plugin publish reads workspace/pm/uv.lock. Re-seed from the
#     checkout whenever it went missing.
for ws in /home/fastfinge/.hermes/installs/*/environments/*/workspace/pm; do
    [[ -d "$ws" ]] || continue
    if [[ ! -f "$ws/uv.lock" && -f "$REPO/pm/uv.lock" ]]; then
        if cp "$REPO/pm/uv.lock" "$ws/uv.lock" 2>/dev/null; then
            REPORT+="plugin workspace: re-seeded pm/uv.lock (was missing)"$'\n\n'
        fi
    fi
done

# 1. Plugins: there is no "update all" subcommand; `hermes plugins update`
#    requires a NAME. Only git-sourced plugins are git-managed and updatable
#    this way (bundled plugins ship with core and update via `hermes update`;
#    `user` plugins are not git clones). Enumerate git plugins from JSON and
#    update each individually so one failure doesn't abort the rest.
#    Self-cloned plugins are not auto-updatable until adopted once
#    (`hermes plugins adopt <name>`); the digest surfaces any refusal.
GIT_PLUGINS="$("$HERMES" plugins list --json 2>/dev/null \
    | python3 -c 'import sys,json; print("\n".join(p["name"] for p in json.load(sys.stdin) if p.get("source")=="git"))' \
    2>/dev/null)"
if [[ -n "$GIT_PLUGINS" ]]; then
    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && continue
        run_step "plugin ${plugin}" "$HERMES" plugins update "$plugin" || true
    done <<< "$GIT_PLUGINS"
fi

# 2. Skills
run_step "skills" "$HERMES" skills update || true

# 3. Sync venv from uv.lock BEFORE `hermes update`.
#    `hermes update` pulls the repo (including uv.lock changes) then runs `uv sync`
#    internally, but if the cron timeout kills it mid-update, the venv is left
#    stale; pyproject/uv.lock say 1.23.0 but the venv still has 1.2.3, and
#    it crashes on next boot.  Running `uv sync` here ensures the venv
#    matches the lock BEFORE the update (which may pull a new lock), and again
#    after (inside `hermes update`).  If the lock changed in step 3, the
#    post-update sync inside `hermes update` handles it; this pre-sync handles
#    the case where a previous update pulled a new lock but the sync didn't
#    complete.
run_step "uv-sync-venv" bash -c "cd $REPO && uv sync --quiet 2>&1" || true

# 4. Hermes core: the security-critical step. NEVER parked/disabled: if this
#    cannot run, the script must scream until it can. `hermes update` restarts
#    the gateway internally and overwrites uncommitted host-tree edits
#    (re-applied in 5a).
HERMES_OUT="$("$HERMES" update --yes 2>&1)"
HERMES_RC=$?
if [[ $HERMES_RC -eq 0 ]]; then
    VERSION_LINE="$(echo "$HERMES_OUT" | grep -E 'Update complete|Already up|up to date' | head -1)"
    REPORT+="hermes update: ${VERSION_LINE:-done}"$'\n\n'
else
    FAILED+="hermes update FAILED (exit ${HERMES_RC}):"$'\n'"$HERMES_OUT"$'\n\n'
fi

# Restarts happen ONLY after a successful update. Never restart the fleet
# onto code that failed to update.
if [[ $HERMES_RC -eq 0 ]]; then
    # 5a. Re-apply the standing host-tree patches the update just clobbered.
    run_step "host-patches" bash "$PATCH_SCRIPT" || true

    # 5b. Restart ALL profile gateways so every profile picks up the new code
    #    then verify the regenerated units pin a BOOTABLE launcher. `hermes gateway restart`
    #    regenerates the unit files as a side effect and pins an
    #    unbootable committed-env launcher. restore the backup units and restart via systemctl directly
    #    (no hermes CLI = no unit regeneration).
    BACKUP_DIR="/home/fastfinge/.hermes/logs/units-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    cp "$UNIT_DIR"/hermes-gateway.service "$UNIT_DIR"/hermes-dashboard.service "$BACKUP_DIR"/ 2>/dev/null
    run_step "gateway restart --all" "$HERMES" gateway restart --all || true

    UNITS_BAD=""
    grep -q 'workspace/\.hermes/bin/hermes' "$UNIT_DIR"/hermes-gateway.service "$UNIT_DIR"/hermes-dashboard.service 2>/dev/null && UNITS_BAD=1
    grep -qF "$EXPECTED_LAUNCHER" "$UNIT_DIR"/hermes-gateway.service 2>/dev/null || UNITS_BAD=1
    if [[ -n "$UNITS_BAD" ]]; then
        if cp "$BACKUP_DIR"/*.service "$UNIT_DIR"/ 2>/dev/null; then
            systemctl --user daemon-reload
            systemctl --user restart hermes-gateway.service
            FAILED+="CRITICAL: regenerated units pinned an unbootable/foreign launcher (workspace/.hermes/bin/hermes signature). Restored pre-restart units from ${BACKUP_DIR} and restarted hermes-gateway.service via systemd directly. Inspect before the next run."$'\n\n'
        else
            FAILED+="CRITICAL: regenerated units pinned an unbootable/foreign launcher AND the unit backup could not be restored from ${BACKUP_DIR}. Manual attention now."$'\n\n'
        fi
    fi

    # 5c. The restart sequence can leave a service stopped on the floor. Verify both units are active afterwards;
    #     quietly start anything that isn't — and scream if it won't come back.
    for svc in hermes-gateway.service hermes-dashboard.service; do
        if [[ "$(systemctl --user is-active "$svc" 2>/dev/null)" != "active" ]]; then
            if systemctl --user start "$svc" 2>/dev/null && sleep 3 && [[ "$(systemctl --user is-active "$svc" 2>/dev/null)" == "active" ]]; then
                REPORT+="${svc} was left stopped after the restart sequence; started it back."$'\n\n'
            else
                FAILED+="${svc} is DOWN after the restart sequence and would not start. Manual attention now."$'\n\n'
            fi
        fi
    done
fi

# Compose final message. Silent if nothing to say.
if [[ -n "$FAILED" ]]; then
    echo "Nightly update had failures."
    echo
    echo "$FAILED"
    if [[ -n "$REPORT" ]]; then
        echo "Successful changes:"
        echo "$REPORT"
    fi
    exit 1
fi

if [[ -n "$REPORT" ]]; then
    echo "Nightly Hermes update — changes:"
    echo
    echo "$REPORT"
fi

# else: silent. Empty stdout = no message.
exit 0
```

### The remaining issues ###

Unfortunately, this script, when run in cron, will restart your Hermes. Hermes does not have any way to restore the status of running jobs, or any way to persist status between reboots or session resets. This means that if the update succeeds, cron will tell you that it failed because the job was interrupted at restart. I have left the reporting infrastructure here in case this ever changes, and so you can modify the script to deliver these reports by email, or in whatever other logging and monitoring infrastructure you have. That will look different depending on your personal system setup, so has been left as a job for the reader. However, if you do not do so, critical information will be thrown away.