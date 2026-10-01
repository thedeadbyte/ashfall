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

    home-manager.users.${cfg.user.name}.dconf.settings = mkMerge [
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
  };
}
