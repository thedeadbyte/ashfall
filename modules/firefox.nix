# Firefox, rebuilt from policy every boot.
{ config, lib, ... }:

let
  cfg = config.ashfall.firefox;
  inherit (lib) mkOption mkEnableOption mkIf types optional optionals concatStringsSep unique;

  passwordManagers = {
    proton-pass = {
      id = "78272b6fa58f4a1abaac99321d503a20@proton.me";
      url = "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi";
      site = "proton.me";
    };
  };
  pm = passwordManagers.${cfg.passwordManager} or null;

  # Sites allowed to run JavaScript (subdomains included). Sign-in pages the
  # enabled features depend on are added automatically.
  allowedSites = unique (
    optional (pm != null) pm.site
    ++ cfg.jsAllowedSites
    ++ optional config.ashfall.tailscale.enable "tailscale.com"
  );

  hostnameSwitches = [
    "no-csp-reports: * true"
    "no-large-media: behind-the-scene false"
  ] ++ optionals cfg.blockJavaScript (
    [ "no-scripting: * true" ]
    ++ map (site: "no-scripting: ${site} false") allowedSites
  );

  forceInstall = id: url: {
    ${id} = { install_url = url; installation_mode = "force_installed"; };
  };
in
{
  options.ashfall.firefox = {
    enable = mkEnableOption "hardened Firefox (uBlock Origin, telemetry off)";

    blockJavaScript = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Turn JavaScript off by default with uBlock Origin; only sites in
        jsAllowedSites (plus required sign-in sites) run scripts. Re-applied
        every time Firefox starts.
      '';
    };

    jsAllowedSites = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "github.com" "duckduckgo.com" ];
      description = "Sites allowed to run JavaScript (subdomains included).";
    };

    passwordManager = mkOption {
      type = types.enum [ "none" "proton-pass" ];
      default = "none";
      description = "Password manager extension to force-install. For others, use extraExtensions.";
    };

    extraExtensions = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        "addon-id@example.org" = "https://addons.mozilla.org/firefox/downloads/latest/<slug>/latest.xpi";
      };
      description = "More extensions to force-install: extension ID mapped to its .xpi URL.";
    };

    verticalTabs = mkOption {
      type = types.bool;
      default = true;
      description = "Show tabs vertically in the sidebar.";
    };

    defaultBrowser = mkOption {
      type = types.bool;
      default = true;
      description = "Register Firefox as the default browser.";
    };
  };

  config = mkIf cfg.enable {
    programs.firefox = {
      enable = true;

      preferences = mkIf cfg.verticalTabs {
        "sidebar.revamp" = true;
        "sidebar.verticalTabs" = true;
      };

      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        PasswordManagerEnabled = false;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        UserMessaging = {
          SkipOnboarding = true;
          ExtensionRecommendations = false;
          FeatureRecommendations = false;
          MoreFromMozilla = false;
        };

        ExtensionSettings =
          forceInstall "uBlock0@raymondhill.net"
            "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
          // (if pm != null then forceInstall pm.id pm.url else { })
          // lib.concatMapAttrs forceInstall cfg.extraExtensions;

        # uBlock Origin re-applies these admin settings at every start
        "3rdparty".Extensions."uBlock0@raymondhill.net".adminSettings = builtins.toJSON {
          hostnameSwitchesString = concatStringsSep "\n" hostnameSwitches;
        };
      };
    };

    home-manager.users.${config.ashfall.user.name}.xdg.mimeApps = mkIf cfg.defaultBrowser {
      enable = true;
      defaultApplications =
        let ff = "firefox.desktop";
        in {
          "text/html" = ff;
          "application/xhtml+xml" = ff;
          "x-scheme-handler/http" = ff;
          "x-scheme-handler/https" = ff;
          "x-scheme-handler/about" = ff;
          "x-scheme-handler/unknown" = ff;
        };
    };
  };
}
