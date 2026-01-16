#!/usr/bin/env bash
# Interactive Nextcloud manual updater for DietPi (Lighttpd + PHP-FPM)
# - Keeps config/ and data/ untouched
# - Creates verbose backups with cp -av
# - Pauses before each step and explains what will happen
# - Writes a detailed log to /var/log/nextcloud-update-<timestamp>.log
#
# Usage:
#   sudo /usr/local/bin/nextcloud-update.sh
#
# Edit VERSION at top to change target release (or answer prompt at run).
set -u

# --------------------
# CONFIG - adjust if needed
# --------------------
DEFAULT_VERSION="32.0.4"
INSTALL_DIR="/var/www/nextcloud"
DATA_DIR="/mnt/dietpi_userdata/nextcloud_data"
WWW_USER="www-data"
TMP_DIR="/tmp"
BACKUP_BASE="/var/backups/nextcloud"
LOG_DIR="/var/log"
DATE_STR="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/nextcloud-update-${DATE_STR}.log"

# --------------------
# Safety + helper funcs
# --------------------
ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 2
  fi
}

log_start() {
  mkdir -p "$LOG_DIR"
  echo "=== Nextcloud manual update started: $(date -Iseconds) ===" | tee -a "$LOG_FILE"
  echo "Install dir: $INSTALL_DIR" | tee -a "$LOG_FILE"
  echo "Data dir:    $DATA_DIR" | tee -a "$LOG_FILE"
  echo "Backup base: $BACKUP_BASE" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

run_and_check() {
  # run command, log stdout/stderr, check return code
  echo "+ $*" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]:-0}
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: command failed with exit code $rc. See $LOG_FILE for details." | tee -a "$LOG_FILE"
    echo "Leaving maintenance mode (if active) and exiting." | tee -a "$LOG_FILE"
    sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" maintenance:mode --off 2>&1 | tee -a "$LOG_FILE" || true
    exit $rc
  fi
}

pause_confirm() {
  echo
  echo ">>> $1"
  echo -n "Press ENTER to continue, or Ctrl+C to abort..."
  read -r _
}

# If script is interrupted, try to leave maintenance mode off
on_exit() {
  rc=$?
  echo "Script exited with code $rc at $(date -Iseconds)" | tee -a "$LOG_FILE"
  # Make sure maintenance mode is off if we set it
  if sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" status 2>/dev/null | grep -q "maintenance: true"; then
    echo "Attempting to disable maintenance mode..." | tee -a "$LOG_FILE"
    sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" maintenance:mode --off 2>&1 | tee -a "$LOG_FILE" || true
  fi
  exit $rc
}
trap on_exit EXIT

# --------------------
# Start
# --------------------
ensure_root

# allow interactive version selection (default provided)
echo "Nextcloud manual updater (interactive)"
echo "Default target version: $DEFAULT_VERSION"
read -r -p "Enter target version (or press ENTER to use $DEFAULT_VERSION): " VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"
DOWNLOAD_URL="https://download.nextcloud.com/server/releases/nextcloud-${VERSION}.zip"

log_start

# Confirm basic paths exist
if [ ! -d "$INSTALL_DIR" ]; then
  echo "ERROR: install dir $INSTALL_DIR does not exist." | tee -a "$LOG_FILE"
  exit 3
fi
if [ ! -d "$DATA_DIR" ]; then
  echo "ERROR: data dir $DATA_DIR does not exist." | tee -a "$LOG_FILE"
  exit 3
fi

echo
echo "Planned actions (summary):"
echo " - Download nextcloud-${VERSION}.zip to $TMP_DIR"
echo " - Enable maintenance mode"
echo " - Backup /var/www/nextcloud (verbose) => $BACKUP_BASE/<timestamp>/"
echo " - Rsync new files from extracted ZIP, excluding config and data"
echo " - chown -R $WWW_USER:$WWW_USER $INSTALL_DIR"
echo " - Run occ upgrade"
echo " - Disable maintenance mode"
echo " - Optional post-upgrade repair commands"
echo
pause_confirm "Review the summary above."

# 1) Download
echo
pause_confirm "About to download $DOWNLOAD_URL into $TMP_DIR (will overwrite same filename if present)."
cd "$TMP_DIR" || exit 4
ZIP_FILE="${TMP_DIR}/nextcloud-${VERSION}.zip"
if [ -f "$ZIP_FILE" ]; then
  echo "Note: $ZIP_FILE already exists. Will overwrite after confirmation." | tee -a "$LOG_FILE"
  read -r -p "Remove existing $ZIP_FILE and download fresh? [Y/n]: " yn
  yn="${yn:-Y}"
  if [[ "$yn" =~ ^[Yy] ]]; then
    run_and_check rm -f "$ZIP_FILE"
  else
    echo "Keeping existing ZIP." | tee -a "$LOG_FILE"
  fi
fi

run_and_check wget -O "$ZIP_FILE" "$DOWNLOAD_URL"

# Optional: show downloaded file size
ls -lh "$ZIP_FILE" | tee -a "$LOG_FILE"

# 2) Enable maintenance mode
pause_confirm "About to enable maintenance mode (occ maintenance:mode --on). This prevents logins and sync during the update."
run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" maintenance:mode --on

# 3) Backups (verbose)
pause_confirm "A backup of current Nextcloud code and config will be made using cp -av. This may take time depending on size."
mkdir -p "$BACKUP_BASE"
BACKUP_DIR="${BACKUP_BASE}/nextcloud_backup_${DATE_STR}"
mkdir -p "$BACKUP_DIR"
echo "Backing up $INSTALL_DIR -> $BACKUP_DIR" | tee -a "$LOG_FILE"
run_and_check cp -a -v "$INSTALL_DIR" "${BACKUP_DIR}/" | tee -a "$LOG_FILE"
echo "Backing up config separately (verbose)." | tee -a "$LOG_FILE"
run_and_check cp -a -v "$INSTALL_DIR/config" "${BACKUP_DIR}/config" | tee -a "$LOG_FILE"

# 4) Extract new version
pause_confirm "Will extract the ZIP to $TMP_DIR/nextcloud (previous extraction will be removed)."
run_and_check rm -rf "${TMP_DIR}/nextcloud"
run_and_check unzip -q "$ZIP_FILE" -d "$TMP_DIR"
if [ ! -d "${TMP_DIR}/nextcloud" ]; then
  echo "ERROR: extracted folder ${TMP_DIR}/nextcloud not found." | tee -a "$LOG_FILE"
  exit 5
fi
echo "Extraction complete." | tee -a "$LOG_FILE"
ls -lh "${TMP_DIR}/nextcloud" | tee -a "$LOG_FILE"

# 5) Rsync new files (preserve config & data)
pause_confirm "Will rsync new files into $INSTALL_DIR preserving config/ and data/ (rsync -av --delete ... --exclude=config --exclude=data)."
run_and_check rsync -av --delete "${TMP_DIR}/nextcloud/" "$INSTALL_DIR/" \
  --exclude=config --exclude=data --exclude=.user.ini --exclude=.htaccess

# 6) Fix ownership
pause_confirm "Set ownership to ${WWW_USER}:${WWW_USER} recursively on $INSTALL_DIR (this may take a moment)."
run_and_check chown -R "${WWW_USER}:${WWW_USER}" "$INSTALL_DIR"

# 7) Run occ upgrade
pause_confirm "About to run 'occ upgrade' to update DB and apps. This can take some time."
run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" upgrade

# 8) Optional DB fixes & repair
echo
read -r -p "Run recommended post-upgrade repair commands? (db:add-missing-indices, db:add-missing-columns, maintenance:repair) [Y/n]: " do_repair
do_repair="${do_repair:-Y}"
if [[ "$do_repair" =~ ^[Yy] ]]; then
  run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" db:add-missing-indices
  run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" db:add-missing-columns
  run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" db:add-missing-primary-keys || true
  run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" maintenance:repair
fi

# 9) Disable maintenance mode
pause_confirm "About to disable maintenance mode (occ maintenance:mode --off)."
run_and_check sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" maintenance:mode --off

# 10) Final status
echo
echo "Final status (occ status):" | tee -a "$LOG_FILE"
sudo -u "$WWW_USER" php "$INSTALL_DIR/occ" status 2>&1 | tee -a "$LOG_FILE"

echo
echo "Update finished at $(date -Iseconds)." | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
echo "Backups saved to: $BACKUP_DIR"
echo
echo "Reminder: if you downloaded ZIP into $TMP_DIR and want to remove it now, you can:"
echo "  rm -f $ZIP_FILE ; rm -rf ${TMP_DIR}/nextcloud"
echo
exit 0
