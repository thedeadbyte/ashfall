# Core: the single user, boot chain, Nix settings, and baseline hardening.
{ config, lib, pkgs, ... }:

let
  cfg = config.ashfall;
  inherit (lib) mkOption mkIf mkDefault types;
in
{
  options.ashfall = {
    user = {
      name = mkOption {
        type = types.str;
        example = "alice";
        description = "Login name of the machine's single user.";
      };
      description = mkOption {
        type = types.str;
        default = cfg.user.name;
        defaultText = lib.literalExpression "config.ashfall.user.name";
        description = "Display name shown on the login screen.";
      };
      uid = mkOption {
        type = types.int;
        default = 1000;
        description = "Fixed uid, so file ownership in /persist stays stable.";
      };
      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [ "networkmanager" "wheel" ];
        description = "Groups for the user. wheel grants sudo.";
      };
      hashedPasswordFile = mkOption {
        type = types.str;
        default = "/persist/secrets/${cfg.user.name}.hash";
        defaultText = lib.literalExpression ''"/persist/secrets/''${config.ashfall.user.name}.hash"'';
        description = ''
          File holding the login password hash. Users are fully declarative
          (/etc is rebuilt every boot), so this file is the only place the
          password lives. Created by the installer; change it with
          `mkpasswd -m yescrypt | sudo tee <file>`.
        '';
      };
    };

    kernel.latest = mkOption {
      type = types.bool;
      default = true;
      description = "Use the newest kernel release instead of the LTS default.";
    };
  };

  config = {
    # ---------- Nix ----------
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.settings.auto-optimise-store = true;
    nix.channel.enable = false; # nixpkgs comes from the flake; nix-shell -p still works
    nix.gc = {
      automatic = mkDefault true;
      dates = mkDefault "weekly";
      options = mkDefault "--delete-older-than 14d";
    };

    # ---------- Boot ----------
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = mkDefault 10;
    boot.loader.efi.canTouchEfiVariables = true;
    # systemd initrd: required for FIDO2 LUKS unlock and the wipe service
    boot.initrd.systemd.enable = true;
    boot.kernelPackages = mkIf cfg.kernel.latest pkgs.linuxPackages_latest;

    zramSwap.enable = mkDefault true;
    services.btrfs.autoScrub.enable = true;

    # ---------- Network baseline ----------
    networking.networkmanager.enable = mkDefault true;
    networking.firewall.enable = true;

    # ---------- Users ----------
    # /etc is rebuilt every boot, so users must be declarative.
    users.mutableUsers = false;
    users.users.root.hashedPassword = "!"; # root login disabled; use sudo
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      uid = cfg.user.uid;
      description = cfg.user.description;
      hashedPasswordFile = cfg.user.hashedPasswordFile;
      extraGroups = cfg.user.extraGroups;
    };
    security.sudo.extraConfig = "Defaults lecture = never";

    # ---------- home-manager ----------
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-bak";
      users.${cfg.user.name} = {
        home.username = cfg.user.name;
        home.homeDirectory = "/home/${cfg.user.name}";
        home.stateVersion = mkDefault config.system.stateVersion;
      };
    };
  };
}
