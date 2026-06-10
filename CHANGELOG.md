## [1.1.1] - 2026.06.10.

### Added
- Added `server/install.sh` as the primary server installer and updater.
- Added `server/yt2nas_server.py` as the versioned Python server file installed to `/opt/yt2nas-server/yt2nas_server.py`.
- Added `/etc/yt2nas-server.env` as the runtime configuration file.
- Added media browsing endpoints for channel folders and channel contents.
- Added a permanent media deletion endpoint for files and folders under the configured media root.
- Added documentation for Android media browser/delete compatibility.

### Changed
- Kept `server/yt2nas-server-setup.sh` as a deprecated compatibility wrapper.
- Reworked server documentation around quick install, migration, troubleshooting, and API usage.

## [1.1.0] - 2026.03.02.

### Added
- if the client cannot reach the server, it stores the received links, which can be sent when the server becomes available again.
- the connection can be tested in the settings menu.

### Fixed
- the refresh button now updates the server status.

## [1.0.1] - 2026.02.25.

- Initial public release.

