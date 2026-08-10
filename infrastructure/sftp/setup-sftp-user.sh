#!/usr/bin/env bash
# setup-sftp-user.sh — create a hardened, chrooted, SFTP-only account for an
# external partner to PULL the nightly Skimmer extracts. Idempotent.
#
# Design (SECURITY_AUDIT_2026-07-14 follow-on; Greenmill file-transfer):
#   - Dedicated system user, NO shell (/usr/sbin/nologin), password LOCKED,
#     key-based auth only, primary group `sftponly`.
#   - ChrootDirectory jail owned root:root 0755 (OpenSSH requires the jail and
#     all parents to be root-owned + non-writable). The partner is dropped into
#     the jail and cannot traverse out, get a shell, or reach the DB socket.
#   - Read-only `extracts/` subdir where the pipeline publishes files. Partner
#     has read only (no write) — tighter than a normal upload jail.
#     INBOUND-ONLY partners (they send us data, we publish nothing to them) set
#     PUBLISH_DIR="" so the directory is never created. An empty `extracts/` in
#     an inbound jail is a foot-gun: it reads as "a place to publish to" and
#     invites a future script to do exactly that.
#   - OPTIONAL write-enabled drop-off subdir (env DROPOFF_DIR, e.g. "incoming"),
#     owned by the partner so they can PUT and DELETE their own files. Only that
#     one subdir is writable; the jail root and `extracts/` stay root-owned, so
#     the chroot requirement holds and published extracts remain tamper-proof.
#     DROPOFF_MODE controls its permissions: 750 (default) or 700 for sensitive
#     sources. All sftp accounts share the `sftponly` primary group, so 750
#     grants group-read to every other partner's account. Chroot makes that
#     unreachable over SFTP today, but a PII drop-off should not rely on a
#     second control for its confidentiality — use 700.
#   - Transfer logging: `internal-sftp -l INFO` records every open/close with
#     filename and byte counts, so a PUT into the drop-off is provable. Without
#     it sshd logs the login only and the audit trail stops at the door.
#   - authorized_keys kept OUTSIDE the jail (/etc/ssh/sftp-keys/%u, root-owned)
#     so the partner can never modify their own key set.
#   - sshd Match block appended to the END of the main config (Match must follow
#     all global directives; Ubuntu's Include sits at the top, so a drop-in would
#     wrongly capture globals). Reload is gated on `sshd -t`.
#
# Does NOT enable ufw — that's a shared-box change (jomo-inventory also serves
# 80/443 here) and needs the partner's source IPs; handled separately.
#
# Usage (run as root on the target box):
#   ./setup-sftp-user.sh [USERNAME] [PUBKEY_FILE]
#   USERNAME    default: sftp-greenmill
#   PUBKEY_FILE optional path to the partner's SSH public key; if omitted the
#               account is created inert (key file empty) until the key arrives.
#   DROPOFF_DIR env; name of a writable drop-off subdir (default: none/read-only).
#               e.g. DROPOFF_DIR=incoming ./setup-sftp-user.sh sftp-greenmill-ci
#   DROPOFF_MODE env; permissions on that subdir. Default 750; use 700 for
#               sensitive (PII) sources.
#   PUBLISH_DIR env; name of the read-only publish subdir. Default "extracts";
#               set to "" for inbound-only partners so it is never created.
#
#   Inbound-only example (BBSI — they send, we publish nothing):
#     PUBLISH_DIR= DROPOFF_DIR=incoming DROPOFF_MODE=700 \
#       ./setup-sftp-user.sh sftp-bbsi /path/to/key.pub
set -euo pipefail

PARTNER_USER="${1:-sftp-greenmill}"
PUBKEY_FILE="${2:-}"
DROPOFF_DIR="${DROPOFF_DIR:-}"      # empty = pull-only account (the default)
DROPOFF_MODE="${DROPOFF_MODE:-750}" # 700 for PII-bearing drop-offs
GROUP="sftponly"
SFTP_ROOT="/srv/sftp"
JAIL="${SFTP_ROOT}/${PARTNER_USER}"
# PUBLISH_DIR is intentionally distinguishable from "set but empty": use
# ${PUBLISH_DIR+x} so `PUBLISH_DIR=` means inbound-only, while an unset var
# keeps the historical "extracts" default for existing pull partners.
PUBLISH_SUB="${PUBLISH_DIR-extracts}"
DATA_DIR="${PUBLISH_SUB:+${JAIL}/${PUBLISH_SUB}}"
KEY_DIR="/etc/ssh/sftp-keys"
KEY_FILE="${KEY_DIR}/${PARTNER_USER}"
CFG="/etc/ssh/sshd_config"
MARK_BEGIN="# >>> sftp-jail (${GROUP}) managed block >>>"
MARK_END="# <<< sftp-jail (${GROUP}) managed block <<<"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root" >&2; exit 1; }

log() { echo ">> $*"; }

# 1. group
if ! getent group "$GROUP" >/dev/null; then groupadd "$GROUP"; log "created group $GROUP"; fi

# 2. user — system account, no shell, no create-home (jail is root-owned)
if ! id "$PARTNER_USER" >/dev/null 2>&1; then
    useradd --system --home-dir "$JAIL" --no-create-home \
            --shell /usr/sbin/nologin --gid "$GROUP" "$PARTNER_USER"
    log "created user $PARTNER_USER"
fi
passwd -l "$PARTNER_USER" >/dev/null 2>&1 || true   # lock password: key-only

# 3. jail + parents must be root:root and non-writable (chroot requirement)
mkdir -p "$SFTP_ROOT" "$JAIL" ${DATA_DIR:+"$DATA_DIR"}
chown root:root "$SFTP_ROOT" "$JAIL" ${DATA_DIR:+"$DATA_DIR"}
chmod 755 "$SFTP_ROOT" "$JAIL" ${DATA_DIR:+"$DATA_DIR"}
[ -n "$DATA_DIR" ] || log "inbound-only: no publish dir created (PUBLISH_DIR empty)"

# 3b. OPTIONAL writable drop-off subdir. Owned by the partner (not root) so they
#     can PUT and DELETE their own files; 0750 keeps it off-limits outside the
#     group. Deliberately NOT the jail root and NOT extracts/ — OpenSSH requires
#     the jail root to stay root-owned, and published extracts must stay
#     tamper-proof. This is the ONLY writable path in the jail.
if [ -n "$DROPOFF_DIR" ]; then
    DROP_PATH="${JAIL}/${DROPOFF_DIR}"
    mkdir -p "$DROP_PATH"
    chown "${PARTNER_USER}:${GROUP}" "$DROP_PATH"
    chmod "$DROPOFF_MODE" "$DROP_PATH"
    log "drop-off ${DROP_PATH} mode ${DROPOFF_MODE}, writable by ${PARTNER_USER} (client sees /${DROPOFF_DIR}/)"
fi

# 4. authorized_keys location outside the jail (partner cannot edit it)
mkdir -p "$KEY_DIR"; chown root:root "$KEY_DIR"; chmod 755 "$KEY_DIR"
if [ -n "$PUBKEY_FILE" ]; then
    [ -f "$PUBKEY_FILE" ] || { echo "ERROR: pubkey $PUBKEY_FILE not found" >&2; exit 1; }
    install -o root -g root -m 644 "$PUBKEY_FILE" "$KEY_FILE"
    log "installed public key into $KEY_FILE"
elif [ ! -f "$KEY_FILE" ]; then
    touch "$KEY_FILE"; chown root:root "$KEY_FILE"; chmod 644 "$KEY_FILE"
    log "created EMPTY key file $KEY_FILE (account inert until a key is added)"
fi

# 5. sshd Match block — appended to END of main config, guarded, idempotent.
#    Rebuilt in place when the desired content changes (e.g. adding `-l INFO`),
#    so re-running this script UPDATES an existing install instead of silently
#    leaving a stale block behind.
#
#    `-l INFO` makes internal-sftp log every open/close with filename and byte
#    counts. This is what turns "someone connected" into "this file was written".
DESIRED_BLOCK="$(cat <<EOF
${MARK_BEGIN}
Match Group ${GROUP}
    ChrootDirectory ${SFTP_ROOT}/%u
    ForceCommand internal-sftp -l INFO
    AuthorizedKeysFile ${KEY_DIR}/%u
    PasswordAuthentication no
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTunnel no
${MARK_END}
EOF
)"

# Fixed-string extraction/removal (markers contain regex metacharacters).
CURRENT_BLOCK="$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{f=1} f{print} $0==e{f=0}' "$CFG")"

if [ "$CURRENT_BLOCK" != "$DESIRED_BLOCK" ]; then
    cp -a "$CFG" "${CFG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    if [ -n "$CURRENT_BLOCK" ]; then
        awk -v b="$MARK_BEGIN" -v e="$MARK_END" \
            '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$CFG" > "${CFG}.new"
        cat "${CFG}.new" > "$CFG"        # preserve inode/perms/ownership
        rm -f "${CFG}.new"
        log "removed stale managed block"
    fi
    printf '\n%s\n' "$DESIRED_BLOCK" >> "$CFG"
    log "wrote managed block to $CFG (backup saved alongside)"
else
    log "managed block already current — no change"
fi

# 6. validate BEFORE reload — abort if config is bad (set -e)
sshd -t
log "sshd -t passed"
systemctl reload ssh
log "reloaded ssh"

log "DONE. user=${PARTNER_USER} jail=${JAIL}${DATA_DIR:+ data=${DATA_DIR}} keys=${KEY_FILE}${DROPOFF_DIR:+ dropoff=${JAIL}/${DROPOFF_DIR} (${DROPOFF_MODE})}"
