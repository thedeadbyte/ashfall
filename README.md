# ashfall

A NixOS laptop that burns down to a clean system on every boot.

Every reboot wipes the system (and, by default, your home folder) and rebuilds it from a config you control. Malware that lands on disk, leftover junk, and settings drift are gone after a restart. Only a short, explicit list of things survives. The disk is always encrypted, and a YubiKey can optionally unlock it.

ashfall is a set of NixOS modules plus a guided installer. You answer a few questions, and it erases one disk, encrypts it, and installs a GNOME desktop with your choices.

## What you get

- **Wipe on boot.** `/` is recreated empty on every boot, and so is `/home` unless you turn that off. NixOS rebuilds everything from `/nix`.
- **Full-disk encryption.** LUKS2 with a passphrase, optionally unlocked by a FIDO2 YubiKey (PIN plus touch).
- **Declarative users.** The login password hash is the only user state kept on disk, and root login is disabled.
- **GNOME**, dark by default, with no first-login wizards. You get a fresh desktop on every boot.
- **Optional feature groups.** The installer asks about each one:

| Group | What it does |
|---|---|
| Hardened Firefox | uBlock Origin, JavaScript off by default with a per-site allowlist, telemetry off, vertical tabs, optional Proton Pass |
| Malware scanning | ClamAV scans every file that lands in `~/Downloads` and quarantines infected ones |
| Tailscale | Ephemeral node: state stays in memory and the device removes itself when offline |
| Developer setup | Neovim with LazyVim, Ghostty (Ctrl+Alt+T), nix-ld for prebuilt language servers |
| YubiKey | Disk unlock, plus `ashfall-secret` for YubiKey-locked secrets you can copy to the clipboard |

## What survives a reboot

| Path | Why |
|---|---|
| `/nix` | the system itself |
| `/etc/nixos` | your config (unless `persistConfig = false`) |
| `/var/lib/nixos` | keeps file ownership stable |
| `/etc/NetworkManager/system-connections` | saved Wi-Fi |
| `/var/lib/bluetooth` | pairings |
| `/etc/machine-id` | stable machine ID |
| `/persist/secrets/<user>.hash` | login password hash |
| plus enabled features | ClamAV signatures, Neovim plugin cache |

Anything else, including Downloads, browser data, shell history, and sign-ins, is gone after a reboot. Add folders you want to keep to `ashfall.persist.userDirectories`.

## Requirements

- An x86_64 PC booting in **UEFI** mode
- One disk you're willing to **erase completely**
- An internet connection during install
- The NixOS 26.05 installer on a USB stick (the graphical ISO is easiest)
- Optional: one or two YubiKey 5 series keys (FIDO2). A spare key is strongly recommended.

## Install

1. Boot the NixOS installer USB. Close the graphical installer window if it opens; ashfall replaces it.
2. Connect to Wi-Fi.
3. Open a terminal and run:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' run github:thedeadbyte/ashfall
```

The installer asks for:
- username, computer name, time zone, and keyboard layout
- which disk to erase, and the swapfile size
- whether to wipe your home folder on boot, and whether to use a YubiKey
- each optional feature group
- a disk passphrase and a login password

It shows a summary and does nothing until you type the disk's name to confirm. Then it partitions and encrypts the disk, enrolls your YubiKeys one at a time if you chose that, and installs. Remove the USB and reboot.

> **Write down the disk passphrase.** If you lose it, and your YubiKeys if you use them, the data is unrecoverable. That's the point of encryption.

## Daily use

Your config is in `/etc/nixos`. To change something, edit it and apply:

```bash
sudo nano /etc/nixos/configuration.nix   # or any editor
sudo nixos-rebuild switch
```

`/etc/nixos` is a git repository, and flakes only see files git knows about. After **adding a new file** (an image, a secret, another `.nix` file), run `sudo git -C /etc/nixos add -A` before rebuilding.

To add an app, look it up at [search.nixos.org](https://search.nixos.org/packages), add it to `environment.systemPackages`, and rebuild.

To update, pull the newest ashfall and nixpkgs, then rebuild:

```bash
cd /etc/nixos
sudo nix flake update
sudo nixos-rebuild switch
```

If an update breaks something, choose an older generation in the boot menu.

**Back up your config.** Push `/etc/nixos` to a *private* git repository. With it, you can reinstall an identical machine at any time (see [Reinstalling](#reinstalling-from-your-own-config)).

## Options

Set these in `configuration.nix` under `ashfall = { ... };`.

| Option | Default | Meaning |
|---|---|---|
| `user.name` | (required) | Login name |
| `user.description` | user name | Name on the login screen |
| `user.extraGroups` | `[ "networkmanager" "wheel" ]` | Groups (`wheel` = sudo) |
| `disk.device` | (required) | Disk to install to |
| `disk.swapSize` | `"8G"` | Swapfile size, or `null` |
| `wipeHome` | `true` | Wipe `/home` on every boot |
| `persistConfig` | `true` | Keep `/etc/nixos` across reboots |
| `persist.directories` / `files` | `[ ]` | Extra system paths to keep |
| `persist.userDirectories` / `userFiles` | `[ ]` | Paths in your home to keep, e.g. `"Documents"` |
| `kernel.latest` | `true` | Newest kernel instead of LTS |
| `desktop.enable` | `true` | GNOME |
| `desktop.darkMode` | `true` | Dark style |
| `desktop.wallpaper` | `null` | Path to an image, e.g. `./wallpaper.jpg` |
| `yubikey.enable` | `false` | YubiKey tools and smart card support |
| `yubikey.luksUnlock` | = `yubikey.enable` | Unlock the disk with a FIDO2 key |
| `yubikey.identities` | `null` | Folder of age identity stubs (from `ashfall-secret init`) |
| `yubikey.clipSecrets.<name>.file` | | Encrypted secret; `<name>` becomes a command |
| `firefox.enable` | `false` | Hardened Firefox |
| `firefox.blockJavaScript` | `true` | JavaScript off except allowed sites |
| `firefox.jsAllowedSites` | `[ ]` | Sites allowed to run JavaScript (subdomains included) |
| `firefox.passwordManager` | `"none"` | `"none"` or `"proton-pass"` |
| `firefox.extraExtensions` | `{ }` | Extension ID mapped to its `.xpi` URL |
| `firefox.verticalTabs` / `defaultBrowser` | `true` | |
| `clamav.enable` | `false` | Scan `~/Downloads` |
| `tailscale.enable` | `false` | Tailscale |
| `tailscale.ephemeral` | `true` | Memory-only state |
| `tailscale.trustInterface` | `false` | Open all ports to your tailnet |
| `dev.enable` | `false` | LazyVim + Ghostty |
| `dev.lazyvim.configDir` | ashfall's | Your own LazyVim folder |
| `dev.lazyvim.persistPlugins` | `true` | Keep the plugin cache across reboots |
| `dev.ghostty.config` | ashfall's | Your own Ghostty config file |

Anything else is standard NixOS. ashfall doesn't stop you from using any NixOS option.

## YubiKey secrets

If you sign in to a password manager on every boot, you can keep its master password encrypted so only your YubiKeys can open it:

```bash
cd /etc/nixos
sudo ashfall-secret init            # once: creates an identity on each plugged-in key
sudo ashfall-secret add vault-pw    # prompts for the secret, encrypts it to all keys
```

Then add the two lines it prints to `configuration.nix`, run `sudo git -C /etc/nixos add -A`, and rebuild. From then on, running `vault-pw` asks for the key's PIN and a touch, then copies the password for a single paste. The clipboard clears after 20 seconds.

The `.age` files and identity stubs are safe to commit. Without a physical key and its PIN, they decrypt nothing.

## Reinstalling from your own config

```bash
# on the NixOS installer USB
nix-shell -p gh git
gh auth login
gh repo clone you/your-config /tmp/config
sudo nix --extra-experimental-features 'nix-command flakes' run github:thedeadbyte/ashfall -- --config /tmp/config --host <name>
```

This skips the questions, reads everything from your config, asks only for the passphrase and password, then erases the disk and installs.

## Using ashfall in an existing flake

```nix
inputs.ashfall.url = "github:thedeadbyte/ashfall";
inputs.nixpkgs.follows = "ashfall/nixpkgs";

# in nixosSystem modules:
ashfall.nixosModules.default
```

Or start from the template: `nix flake init -t github:thedeadbyte/ashfall`.

## What this protects against, and what it doesn't

**Protects against**
- A stolen or lost laptop. The disk is encrypted, and the YubiKey option requires the key plus its PIN.
- Malware and tampering that persist on disk. They're wiped at reboot, unless they land in a persisted path.
- Configuration drift. The running system is always your config, rebuilt fresh.

**Doesn't protect against**
- **Anything during a session.** Until you reboot, malware can read what you can read, including live browser sessions and tokens.
- **Persisted paths.** Everything on the keep list survives by design, including the Neovim plugin cache if the developer setup is on.
- **Evil-maid attacks.** `/boot` isn't encrypted and Secure Boot isn't set up, so someone with physical access could tamper with the kernel to capture your passphrase.
- **Data loss.** Wiping is the point. Keep anything important somewhere else.

## Limitations

GNOME only, x86_64 only, one user, and one whole disk. The disk layout (partition labels, the `cryptroot` mapper name, and subvolume names) is fixed once installed.

## Forking

Change `flakeRef` in `flake.nix` to your repo so installer-generated configs follow your fork.
