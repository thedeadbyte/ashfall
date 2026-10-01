# Burn on boot.
#
# Before / (and /home) are mounted, the initrd deletes those btrfs
# subvolumes and recreates them empty. NixOS then rebuilds /etc, /var, and
# the home directory from the store. Only paths listed in
# environment.persistence."/persist" survive; other modules add to that list
# through the ashfall.persist options.
{ config, lib, ... }:

let
  cfg = config.ashfall;
  inherit (lib) mkOption types optional concatStringsSep;
  wiped = [ "root" ] ++ optional cfg.wipeHome "home";
in
{
  options.ashfall = {
    wipeHome = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Wipe /home on every boot as well as /. If false, the home directory
        is kept, which is more convenient but lets user-level malware and
        clutter survive reboots.
      '';
    };

    persistConfig = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Keep /etc/nixos across reboots so the system config can be edited
        and rebuilt locally with `sudo nixos-rebuild switch`. Set to false if
        the config lives only in a git remote and is cloned when needed.
      '';
    };

    persist = {
      directories = mkOption {
        type = types.listOf types.anything;
        default = [ ];
        example = [ "/var/lib/libvirt" ];
        description = "Extra system directories to keep (impermanence syntax).";
      };
      files = mkOption {
        type = types.listOf types.anything;
        default = [ ];
        description = "Extra system files to keep.";
      };
      userDirectories = mkOption {
        type = types.listOf types.anything;
        default = [ ];
        example = [ "Documents" { directory = ".ssh"; mode = "0700"; } ];
        description = "Directories in the user's home to keep (relative paths).";
      };
      userFiles = mkOption {
        type = types.listOf types.anything;
        default = [ ];
        description = "Files in the user's home to keep (relative paths).";
      };
    };
  };

  config = {
    fileSystems."/persist".neededForBoot = true;
    # /home must be mounted in the initrd so the home directory is created on
    # the fresh subvolume, not on the root underneath it
    fileSystems."/home".neededForBoot = true;

    boot.initrd.systemd.services.rollback = {
      description = "Wipe btrfs root and home subvolumes";
      wantedBy = [ "initrd.target" ];
      requires = [ "dev-mapper-cryptroot.device" ];
      after = [ "dev-mapper-cryptroot.device" "systemd-cryptsetup@cryptroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        mount -t btrfs -o subvol=/ /dev/mapper/cryptroot /btrfs_tmp

        delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
        }

        for sv in ${concatStringsSep " " wiped}; do
          if [ -e "/btrfs_tmp/$sv" ]; then
            echo "rollback: wiping $sv"
            delete_subvolume_recursively "/btrfs_tmp/$sv"
          fi
          echo "rollback: creating fresh $sv"
          btrfs subvolume create "/btrfs_tmp/$sv"
        done

        umount /btrfs_tmp
      '';
    };

    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        # uid/gid allocation map; keeps file ownership stable across boots
        "/var/lib/nixos"
        # saved Wi-Fi networks
        { directory = "/etc/NetworkManager/system-connections"; mode = "0700"; }
        # Bluetooth pairings (only used if hardware.bluetooth is enabled)
        "/var/lib/bluetooth"
      ]
      ++ optional cfg.persistConfig "/etc/nixos"
      ++ cfg.persist.directories;
      files = [ "/etc/machine-id" ] ++ cfg.persist.files;
      users.${cfg.user.name} = {
        directories = cfg.persist.userDirectories;
        files = cfg.persist.userFiles;
      };
    };
    # The login password hash in /persist/secrets is read directly by
    # users.users.<name>.hashedPasswordFile; it is not bind-mounted.
  };
}
