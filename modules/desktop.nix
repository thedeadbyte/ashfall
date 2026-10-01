# GNOME desktop tuned for a home directory that is new on every boot.
{ config, lib, pkgs, ... }:

let
  cfg = config.ashfall;
  inherit (lib) mkOption mkIf mkMerge types optional;
in
{
  options.ashfall.desktop = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "GNOME desktop with GDM and PipeWire audio.";
    };
    darkMode = mkOption {
      type = types.bool;
      default = true;
      description = "Always use the dark style.";
    };
    wallpaper = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./wallpaper.jpg";
      description = "Image used for the desktop (light and dark) and lock screen.";
    };
    downloadsOnly = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Create only ~/Downloads in the home directory. The other standard
        folders (Desktop, Documents, Music, Pictures, Projects, Public,
        Templates, Videos) are left out and GNOME's xdg-user-dirs is told not
        to recreate them at login; apps asking for one of those get the home
        folder instead. The home directory is new on every boot, so there is
        nothing to keep in them. Set to false for the normal GNOME set.
      '';
    };
  };

  config = mkIf cfg.desktop.enable {
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;
    # Every boot is a new home directory; skip first-login wizards
    services.gnome.gnome-initial-setup.enable = false;
    environment.gnome.excludePackages =
      [ pkgs.gnome-tour ]
      # Firefox replaces GNOME Web when ashfall.firefox is on
      ++ optional cfg.firefox.enable pkgs.epiphany;
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    home-manager.users.${cfg.user.name} = {
      dconf.settings = mkMerge [
        { "org/gnome/shell".welcome-dialog-last-shown-version = "999"; }

        (mkIf cfg.desktop.darkMode {
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-theme = "Adwaita-dark";
          };
        })

        (mkIf (cfg.desktop.wallpaper != null) {
          "org/gnome/desktop/background" = {
            picture-uri = "file://${cfg.desktop.wallpaper}";
            picture-uri-dark = "file://${cfg.desktop.wallpaper}";
            picture-options = "zoom";
          };
          "org/gnome/desktop/screensaver" = {
            picture-uri = "file://${cfg.desktop.wallpaper}";
            picture-options = "zoom";
          };
        })
      ];

      # Writes ~/.config/user-dirs.dirs with a single XDG_DOWNLOAD_DIR entry,
      # plus ~/.config/user-dirs.conf with enabled=False so xdg-user-dirs
      # leaves the rest alone. The null folders are never created.
      xdg.userDirs = mkIf cfg.desktop.downloadsOnly {
        enable = true;
        createDirectories = true;
        download = "/home/${cfg.user.name}/Downloads";
        desktop = null;
        documents = null;
        music = null;
        pictures = null;
        projects = null;
        publicShare = null;
        templates = null;
        videos = null;
      };
    };
  };
}
