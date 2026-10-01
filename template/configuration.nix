# Machine config built on ashfall. Edit, then apply with:
#   sudo nixos-rebuild switch
# The installer writes a filled-in copy of this file for you.
{ pkgs, ... }:

{
  networking.hostName = "ashfall"; # must match the name in flake.nix
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb.layout = "us";
  console.useXkbConfig = true; # same layout at the disk-unlock prompt

  ashfall = {
    user.name = "alice";
    disk.device = "/dev/nvme0n1"; # erased by the installer
    disk.swapSize = "8G";         # null for no swapfile

    # Wipe /home on every boot too (recommended)
    wipeHome = true;
    # Keep /etc/nixos (this config) across reboots
    persistConfig = true;

    # Unlock the disk with a FIDO2 YubiKey (PIN + touch)
    yubikey.enable = false;

    # Firefox: uBlock Origin, telemetry off, JavaScript off by default
    firefox = {
      enable = true;
      blockJavaScript = true;
      jsAllowedSites = [ ];
      passwordManager = "none"; # or "proton-pass"
    };

    # Scan everything that lands in ~/Downloads
    clamav.enable = true;

    # Ephemeral Tailscale node (sign in each boot with `tsup`)
    tailscale.enable = false;

    # LazyVim + Ghostty (Ctrl+Alt+T)
    dev.enable = false;

    # Anything else you want to survive reboots
    persist.directories = [ ];
    persist.userDirectories = [ ];
  };

  # Your packages
  environment.systemPackages = with pkgs; [ ];

  system.stateVersion = "26.05"; # Do not change after install
}
