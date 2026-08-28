#!/usr/bin/env bash
# archive-incoming.sh — copy VERIFIED partner uploads out of the SFTP jail into a
# root-owned archive.
#
# WHY THIS EXISTS: `incoming/` is partner-writable by definition — that is the
# whole point of a drop-off. A file sitting there is therefore not yet a backup:
# the partner (or anyone holding that key) can overwrite or delete it, and our
# only copy goes with it. Governance data we were asked to retain has to leave
# the writable surface before it counts as retained.
#
# Only files whose sidecar manifest verifies are archived. An unverified file is
# left in place and reported — we do not quietly preserve bytes we cannot vouch
# for, because a corrupt archive that looks authoritative is worse than none.
#
# THIS SCRIPT NEVER DELETES FROM THE DROP-OFF. It copies. Greenmill retains their
# uploads in `incoming/` in perpetuity and sweeps them by hand (Ross, 2026-08-06),
# so draining the directory would destroy the partner's own working set. Our copy
# is an ADDITIONAL guarantee, not a relocation.
#
# Idempotent: a payload already archived with a matching sha256 is skipped, so
# this is safe to run on a schedule. A DIFFERENT payload arriving under a name
# already archived is never overwritten — it lands beside it with a .conflict
# suffix and is reported loudly.
#
# SCALE BREAKPOINT: because nothing is ever removed, every run re-hashes every
# retained file (source, plus the archived copy on the skip path). At ~1.4 MB/day
# that is a second or two after a year and not worth optimising. If a partner ever
# drops multi-GB files daily, switch the skip test to size+mtime and re-verify on a
# weekly sweep instead — do NOT simply drop the verification.
#
# Cron — 00:30 UTC, shortly after Greenmill's ~23:56 UTC push and well before the
# 05:30 pipeline, so the nightly report reads an already-archived state:
#   30 0 * * * /opt/splashworks/infrastructure/sftp/archive-incoming.sh >> /opt/splashworks/data/sftp-archive.log 2>&1
set -euo pipefail
shopt -s nullglob

DROPOFF_GLOB="${SFTP_DROPOFF_GLOB:-/srv/sftp/*/incoming}"
ARCHIVE_ROOT="${PARTNER_ARCHIVE_DIR:-/opt/splashworks/data/partner-incoming}"
ts() { date -u +%FT%TZ; }

archived=0; skipped=0; failed=0

for d in $DROPOFF_GLOB; do
    [ -d "$d" ] || continue
    account="$(basename "$(dirname "$d")")"
    dest="${ARCHIVE_ROOT}/${account}"
    install -d -o root -g root -m 750 "$dest"

    for manifest in "$d"/*.manifest.json; do
        # `file` is partner-controlled: force it to a bare basename so a crafted
        # manifest cannot make us read or write outside these two directories.
        payload_name="$(python3 -c '
import json,os,sys
try:
    d=json.load(open(sys.argv[1]))
    f=str(d.get("file","")).strip()
    print(os.path.basename(f) if f and f==os.path.basename(f) and f not in (".","..") else "")
except Exception:
    print("")' "$manifest")"

        if [ -z "$payload_name" ]; then
            echo "$(ts) FAIL ${account}: unusable manifest $(basename "$manifest")" >&2
            failed=$((failed + 1)); continue
        fi

        src="${d}/${payload_name}"
        if [ ! -f "$src" ]; then
            echo "$(ts) FAIL ${account}: ${payload_name} declared by $(basename "$manifest") but absent" >&2
            failed=$((failed + 1)); continue
        fi

        want="$(python3 -c 'import json,sys;print(str(json.load(open(sys.argv[1])).get("sha256","")).lower())' "$manifest")"
        got="$(sha256sum "$src" | cut -d" " -f1)"
        if [ "$want" != "$got" ]; then
            echo "$(ts) FAIL ${account}: ${payload_name} sha256 mismatch — NOT archived" >&2
            failed=$((failed + 1)); continue
        fi

        target="${dest}/${payload_name}"
        if [ -f "$target" ]; then
            if [ "$(sha256sum "$target" | cut -d' ' -f1)" = "$got" ]; then
                skipped=$((skipped + 1)); continue          # already have this exact payload
            fi
            # Same name, different bytes. Never overwrite: the archived copy may
            # be the only surviving record of the earlier version.
            target="${target}.conflict.$(date -u +%Y%m%dT%H%M%SZ)"
            echo "$(ts) WARN ${account}: ${payload_name} differs from the archived copy — saved as $(basename "$target")" >&2
        fi

        install -o root -g root -m 640 "$src" "${target}.part"
        mv -f "${target}.part" "$target"
        # Preserve the partner's OWN manifest filename so the archive is a faithful
        # copy of the drop-off. The earlier form appended .manifest.json to the
        # payload name, producing `<file>.json.gz.manifest.json` in the archive while
        # the jail held `<file>.manifest.json` — the archive stopped matching the
        # convention its own `file` field describes, so a restore tool written against
        # the partner's layout would not find the sidecar. Data was never affected.
        # On a CONFLICT the payload was renamed, so the manifest is paired to it
        # explicitly — otherwise the second manifest would clobber the first.
        if [ "$target" = "${dest}/${payload_name}" ]; then
            install -o root -g root -m 640 "$manifest" "${dest}/$(basename "$manifest")"
        else
            install -o root -g root -m 640 "$manifest" "${target}.manifest.json"
        fi
        echo "$(ts) archived ${account}/${payload_name} ($(stat -c %s "$target") bytes, sha256 ${got:0:16}…)"
        archived=$((archived + 1))
    done
done

echo "$(ts) done — ${archived} archived, ${skipped} already present, ${failed} failed"
[ "$failed" -eq 0 ]
