# ClamAV daemon, signature updates, and a user service that scans every file
# landing in ~/Downloads. Infected files go to ~/.quarantine (chmod 000) with
# a desktop notification.
{ config, lib, pkgs, ... }:

let
  cfg = config.ashfall.clamav;

  clamWatch = pkgs.writeShellScript "clamav-downloads-watch" ''
    set -u
    watch_dir="$HOME/Downloads"
    quarantine_dir="$HOME/.quarantine"
    mkdir -p "$watch_dir" "$quarantine_dir"
    chmod 700 "$quarantine_dir"

    echo "[clamwatch] watching $watch_dir, quarantine at $quarantine_dir"

    inotifywait -m -q -e close_write,moved_to --format '%w%f' "$watch_dir" |
    while IFS= read -r file; do
      # Skip in-progress browser temp files; the final rename triggers moved_to
      case "$file" in
        *.part|*.crdownload|*.tmp|*.download) continue ;;
      esac
      [ -f "$file" ] || continue

      name=$(basename "$file")
      echo "[clamwatch] scanning: $file"
      output=$(clamdscan --config-file=/etc/clamav/clamd.conf --fdpass --no-summary "$file" 2>&1)
      rc=$?

      case $rc in
        0)
          echo "[clamwatch] clean: $file"
          ;;
        1)
          sig=$(printf '%s\n' "$output" | sed -n 's/.*: \(.*\) FOUND$/\1/p' | head -n1)
          dest="$quarantine_dir/$(date +%Y%m%d-%H%M%S)-$name"
          if mv -- "$file" "$dest"; then
            chmod 000 "$dest"
            echo "[clamwatch] INFECTED ($sig): $file moved to $dest"
            notify-send -u critical -i dialog-warning "ClamAV: threat quarantined" "$name: $sig"
          else
            echo "[clamwatch] INFECTED ($sig): $file, quarantine move FAILED"
            notify-send -u critical -i dialog-error "ClamAV: threat found, quarantine failed" "$name: $sig"
          fi
          ;;
        *)
          echo "[clamwatch] scan error (rc=$rc) on $file: $output"
          notify-send -u normal -i dialog-warning "ClamAV: scan failed" "$name (see journalctl --user -u clamav-downloads)"
          ;;
      esac
    done
  '';
in
{
  options.ashfall.clamav.enable = lib.mkEnableOption "ClamAV with on-arrival scanning of ~/Downloads";

  config = lib.mkIf cfg.enable {
    services.clamav.daemon.enable = true;
    services.clamav.updater.enable = true;

    systemd.user.services.clamav-downloads = {
      description = "ClamAV scan of new files in ~/Downloads";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      path = with pkgs; [ inotify-tools clamav libnotify coreutils gnused ];
      serviceConfig = {
        ExecStart = "${clamWatch}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    environment.systemPackages = [ pkgs.clamav ];

    # Keep the ~300MB signature database instead of re-downloading every boot
    ashfall.persist.directories = [
      { directory = "/var/lib/clamav"; user = "clamav"; group = "clamav"; mode = "0755"; }
    ];

    programs.bash.shellAliases.clamlog = "journalctl --user -u clamav-downloads -f";
  };
}
