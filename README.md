# Nextcloud Manual Updater for DietPi

This interactive script updates your Nextcloud installation on DietPi (with Lighttpd + PHP-FPM), keeping the `config/` and `data/` directories untouched. It's optimized for setups like yours on the Android T95-Max-Plus box.

## Features

- **Verbose Backups**: Creates detailed backups using `cp -av`.
- **Interactive Mode**: Pauses before each step for confirmation.
- **Detailed Logs**: Records everything to `/var/log/nextcloud-update-<timestamp>.log`.
- **Security**: Enables/disables maintenance mode and fixes permissions.
- **Optional**: Runs post-upgrade repairs (DB indices, columns, etc.).

## Prerequisites

- DietPi with Nextcloud installed in `/var/www/nextcloud`.
- Data in `/mnt/dietpi_userdata/nextcloud_data` (adjust in the script if different).
- `wget`, `unzip`, and `rsync` installed (standard on DietPi).
- Run as root: `sudo /usr/local/bin/nextcloud-update.sh`.

## Installation

1. Copy the script to `/usr/local/bin/nextcloud-update.sh`.
2. Make it executable: `chmod +x /usr/local/bin/nextcloud-update.sh`.
3. Edit `DEFAULT_VERSION` at the top of the script for the desired version (you can also change it interactively).

## Usage

```bash
sudo /usr/local/bin/nextcloud-update.sh
```

## Configuration

Edit the variables at the top of the script:

- `DEFAULT_VERSION`: Nextcloud version (e.g., "32.0.4").
- `INSTALL_DIR` and `DATA_DIR`: Installation paths.

## Warnings

- **Test in a staging environment first!**
- Backups go to `/var/backups/nextcloud/<timestamp>/`.
- If interrupted, the script attempts to disable maintenance mode.
- Compatible with Nextcloud 20+; check the [official documentation](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/update.html).

## License

MIT License - see [LICENSE](LICENSE).

## Contributions

Forks and pull requests welcome! Report issues for bugs or improvements.

Made for DietPi on the T95-Max-Plus. 😊
