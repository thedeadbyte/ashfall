# Developer setup: Neovim with LazyVim, Ghostty, and the tools they need.
{ config, lib, pkgs, ... }:

let
  cfg = config.ashfall.dev;
  user = config.ashfall.user.name;
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types optional;
in
{
  options.ashfall.dev = {
    enable = mkEnableOption "developer setup (LazyVim, Ghostty)";

    lazyvim = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Neovim with a LazyVim config.";
      };
      configDir = mkOption {
        type = types.path;
        default = ../assets/nvim;
        defaultText = lib.literalExpression "ashfall's assets/nvim";
        description = ''
          LazyVim config folder. Copied (not symlinked) into ~/.config/nvim at
          every login so LazyVim can write its lock and state files; edits
          made there vanish on reboot, so change this source instead.
        '';
      };
      persistPlugins = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Keep ~/.local/share/nvim (plugins, parsers, Mason tools) so Neovim
          doesn't re-download them every boot. This is downloaded code, not
          personal data, but it does persist and run on every launch.
        '';
      };
    };

    ghostty = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Ghostty terminal.";
      };
      config = mkOption {
        type = types.path;
        default = ../assets/ghostty/config;
        defaultText = lib.literalExpression "ashfall's assets/ghostty/config";
        description = "Ghostty config file.";
      };
      shortcut = mkOption {
        type = types.bool;
        default = true;
        description = "Open Ghostty with Ctrl+Alt+T in GNOME.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.lazyvim.enable {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
      };
      # Mason downloads prebuilt language servers; nix-ld lets them run
      programs.nix-ld.enable = true;

      environment.systemPackages = with pkgs; [
        ripgrep fd fzf gcc gnumake tree-sitter nodejs wl-clipboard lazygit git
        nil nixfmt statix
      ];

      ashfall.persist.userDirectories = optional cfg.lazyvim.persistPlugins ".local/share/nvim";

      home-manager.users.${user} = { lib, ... }: {
        home.activation.lazyvimConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run rm -rf "$HOME/.config/nvim"
          run mkdir -p "$HOME/.config"
          run cp -r --no-preserve=mode ${cfg.lazyvim.configDir} "$HOME/.config/nvim"
        '';
      };
    })

    (mkIf cfg.ghostty.enable {
      environment.systemPackages = [ pkgs.ghostty ];
      fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

      home-manager.users.${user} = {
        xdg.configFile."ghostty/config".source = cfg.ghostty.config;

        dconf.settings = mkIf (cfg.ghostty.shortcut && config.ashfall.desktop.enable) {
          "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/"
          ];
          "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty" = {
            name = "Ghostty";
            command = "ghostty";
            binding = "<Control><Alt>t";
          };
        };
      };
    })
  ]);
}
