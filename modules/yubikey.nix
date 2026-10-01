# Optional YubiKey support.
#
# - luksUnlock: the initrd asks for a FIDO2 key (PIN + touch) to unlock the
#   disk, falling back to the recovery passphrase after 30s. Keys are
#   enrolled by the installer (or later with systemd-cryptenroll).
# - clipSecrets: small age-encrypted secrets (for example a password-manager
#   master password) that only your YubiKeys can decrypt. Each one becomes a
#   command that copies the secret to the clipboard for a single paste.
#   Create them with `ashfall-secret`.
{ config, lib, pkgs, ... }:

let
  cfg = config.ashfall.yubikey;
  inherit (lib) mkOption mkEnableOption mkIf types mapAttrsToList;

  clipCommand = name: secret: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [ age age-plugin-yubikey yubikey-manager wl-clipboard coreutils gnugrep ];
    text = ''
      secret="${secret.file}"
      ids="${cfg.identities}"
      clear_after=${toString secret.clearAfter}

      echo "[1/3] Looking for a YubiKey..."
      connected=$(ykman list --serials 2>/dev/null || true)
      identity=""
      for f in "$ids"/*.txt; do
        serial=$(grep -o 'Serial: [0-9]*' "$f" | grep -o '[0-9]*' | head -n1)
        if [ -n "$serial" ] && printf '%s\n' "$connected" | grep -qx "$serial"; then
          identity="$f"
          echo "  using $(basename "$f" .txt) key (serial $serial)"
          break
        fi
      done
      if [ -z "$identity" ]; then
        echo "  no enrolled YubiKey found; plug one in and try again" >&2
        exit 1
      fi

      echo "[2/3] Decrypting: enter your PIV PIN, then touch the key when it blinks"
      pw=$(age -d -i "$identity" "$secret")

      printf '%s' "$pw" | wl-copy --paste-once
      unset pw
      ( sleep "$clear_after"; wl-copy --clear ) >/dev/null 2>&1 &
      disown

      echo "[3/3] Copied. Clears after one paste or ''${clear_after}s."
    '';
  };

  secretTool = pkgs.writeShellApplication {
    name = "ashfall-secret";
    runtimeInputs = with pkgs; [ age age-plugin-yubikey yubikey-manager coreutils gnugrep ];
    text = builtins.readFile ../installer/ashfall-secret.sh;
  };
in
{
  options.ashfall.yubikey = {
    enable = mkEnableOption "YubiKey support (smart card daemon, tools, ashfall-secret)";

    luksUnlock = mkOption {
      type = types.bool;
      default = cfg.enable;
      defaultText = lib.literalExpression "config.ashfall.yubikey.enable";
      description = "Ask for an enrolled FIDO2 key at boot to unlock the disk.";
    };

    identities = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./secrets/identities";
      description = ''
        Folder of age-plugin-yubikey identity stubs (one .txt per key). They
        point at a key's serial and slot and contain no private material.
      '';
    };

    clipSecrets = mkOption {
      default = { };
      example = lib.literalExpression ''
        { proton-pw.file = ./secrets/proton-pw.age; }
      '';
      description = "Secrets exposed as copy-to-clipboard commands, named by attribute.";
      type = types.attrsOf (types.submodule {
        options = {
          file = mkOption {
            type = types.path;
            description = "age file encrypted to your YubiKey recipients.";
          };
          clearAfter = mkOption {
            type = types.int;
            default = 20;
            description = "Seconds before the clipboard is cleared.";
          };
        };
      });
    };
  };

  config = lib.mkMerge [
  # The key must be usable in the initrd to unlock the disk
  (mkIf cfg.luksUnlock {
    boot.initrd.availableKernelModules = [ "usbhid" ];
  })

  (mkIf cfg.enable {
    assertions = [{
      assertion = cfg.clipSecrets == { } || cfg.identities != null;
      message = "ashfall.yubikey.clipSecrets needs ashfall.yubikey.identities set.";
    }];

    # pcscd = smart card daemon, required for PIV (age-plugin-yubikey)
    services.pcscd.enable = true;
    services.udev.packages = [ pkgs.yubikey-personalization ];

    environment.systemPackages = with pkgs; [
      yubikey-manager
      age
      age-plugin-yubikey
      secretTool
    ] ++ mapAttrsToList clipCommand cfg.clipSecrets;
  })
  ];
}
