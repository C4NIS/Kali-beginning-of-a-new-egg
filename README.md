# setup-tor-proxychains.sh

A fully automated, **idempotent Bash script** to update your system, install and enable **Tor**, and configure **Proxychains** for secure, anonymized traffic routing on Linux.
Compatible with **Debian/Ubuntu/Kali**, **Arch/Manjaro**, **Fedora**, and **openSUSE**.

---

## What It Does

* Detects your package manager (`apt`, `pacman`, `dnf`, or `zypper`).
* Runs full system update (`update` + `upgrade`).
* Installs **Tor** and a compatible version of **Proxychains** (`proxychains-ng`, `proxychains4`, or `proxychains`).
* Enables and starts the Tor service via **systemd** (if available).
* Creates backups of all modified configuration files under `/root/setup-backups-YYYYMMDD-HHMMSS/`.
* Updates `/etc/tor/torrc` with essential Tor settings:

  * `SocksPort 9050`
  * `DNSPort 5353`
  * `AutomapHostsOnResolve 1`
  * `VirtualAddrNetworkIPv4 10.192.0.0/10`
* Configures Proxychains to use Tor:

  * Enables `proxy_dns`
  * Sets `dynamic_chain`
  * Ensures `socks5 127.0.0.1 9050` at the bottom of the config
* Restarts Tor to apply changes.

---

## Requirements

* Root privileges (script relaunches itself with `sudo` if not run as root)
* Internet connection
* A supported package manager:

  * `apt` (Debian, Ubuntu, Kali)
  * `pacman` (Arch, Manjaro)
  * `dnf` (Fedora)
  * `zypper` (openSUSE)
* Optional: `systemd` for automatic Tor service management

---

## Usage

1. Save the script as:

   ```bash
   setup-tor-proxychains.sh
   ```
2. Make it executable:

   ```bash
   chmod +x setup-tor-proxychains.sh
   ```
3. Run it:

   ```bash
   ./setup-tor-proxychains.sh
   ```

   If not running as root, the script will prompt for `sudo` access.

---

## Backups and Logs

* Every run creates a timestamped backup in:

  ```
  /root/setup-backups-YYYYMMDD-HHMMSS/
  ```

  This includes:

  * `/etc/tor/torrc`
  * `/etc/proxychains*.conf` (if present)

---

## Quick Tests

Check if Tor is running:

```bash
pgrep -a tor
# or
systemctl status tor.service
```

Verify Tor connectivity:

```bash
proxychains4 curl https://check.torproject.org
# or
proxychains curl https://check.torproject.org
```

You should see a message stating that your IP address is part of the Tor network.

---

## Important Notes

* **Idempotent:** You can safely re-run it; it won’t duplicate config entries.
* **Default Ports:**

  * Tor SOCKS: `9050`
  * Tor DNS: `5353`
* **Tor User:** On some systems, the Tor service runs as `tor`, others as `debian-tor`. The script attempts to fix permissions automatically.
* **Proxychains binary name:** May vary (`proxychains`, `proxychains4`, or `proxychains-ng`).
* **WSL (Windows Subsystem for Linux):** Works partially; WSL might not support `systemd`, so Tor must be launched manually using `tor &`.

---

## Restore / Revert

Backups are stored in `/root/setup-backups-*`.
To revert manually:

```bash
cp /root/setup-backups-YYYYMMDD-HHMMSS/torrc.YYYYMMDD-HHMMSS.bak /etc/tor/torrc
systemctl restart tor.service
```

---

## Customization Ideas

* Change `dynamic_chain` to `strict_chain` in Proxychains for stricter routing.
* Modify `SocksPort` in `/etc/tor/torrc` if another service already uses 9050.
* Add custom exit nodes or log levels (advanced users only).
* Combine with firewall rules (`iptables`, `ufw`) to force all traffic through Tor.

---

## Troubleshooting

**Tor doesn’t start:**
Run:

```bash
journalctl -u tor.service -b
```

Check permissions on `/var/log/tor` and the Tor service user.

**Proxychains not routing properly:**

* Confirm the executable name with `which proxychains4` or `which proxychains`.
* Ensure the config file ends with:

  ```
  socks5 127.0.0.1 9050
  ```

**Direct connection bypasses Tor:**
Try manually:

```bash
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org
```

---

## License

```
MIT License
Copyright (c) 2025 <Your Name>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”),
to deal in the Software without restriction...
```

---

## Final Notes

This script is ideal for:

* Ethical hackers and penetration testers who want Tor + Proxychains ready fast.
* Researchers setting up controlled anonymous environments.
* Power users automating fresh Linux setups.

