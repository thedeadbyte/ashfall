# Disk layout, declared with disko and used by the installer to partition.
#
#   <device>p1  1G    ESP (vfat)        -> /boot
#   <device>p2  rest  LUKS2 "cryptroot"
#                     └─ btrfs
#                        ├─ root     -> /          wiped every boot
#                        ├─ home     -> /home      wiped every boot (optional)
#                        ├─ nix      -> /nix       kept: the system itself
#                        ├─ persist  -> /persist   kept: small, explicit list
#                        └─ swap     -> /.swapvol  swapfile (optional)
#
# The names here (disk "main", partitions "ESP"/"luks", mapper "cryptroot")
# are part of the on-disk contract: changing them on an installed machine
# stops it from booting.
{ config, lib, ... }:

let
  cfg = config.ashfall.disk;
  inherit (lib) mkOption types optionalAttrs optional;
  btrfsOpts = [ "compress=zstd" "noatime" ];
in
{
  options.ashfall.disk = {
    device = mkOption {
      type = types.str;
      example = "/dev/nvme0n1";
      description = "Whole disk to install to. The installer erases it.";
    };
    swapSize = mkOption {
      type = types.nullOr types.str;
      default = "8G";
      example = "16G";
      description = "Size of the btrfs swapfile, or null for zram only.";
    };
  };

  config.disko.devices.disk.main = {
    type = "disk";
    device = cfg.device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # Only read while the installer formats the disk
            passwordFile = "/tmp/luks-recovery.pass";
            settings = {
              allowDiscards = true;
              crypttabExtraOpts = optional config.ashfall.yubikey.luksUnlock "fido2-device=auto";
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = { mountpoint = "/"; mountOptions = btrfsOpts; };
                "/home" = { mountpoint = "/home"; mountOptions = btrfsOpts; };
                "/nix" = { mountpoint = "/nix"; mountOptions = btrfsOpts; };
                "/persist" = { mountpoint = "/persist"; mountOptions = btrfsOpts; };
              } // optionalAttrs (cfg.swapSize != null) {
                "/swap" = {
                  mountpoint = "/.swapvol";
                  swap.swapfile.size = cfg.swapSize;
                };
              };
            };
          };
        };
      };
    };
  };
}
