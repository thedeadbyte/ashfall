# Tailscale. By default the node is ephemeral: its state lives only in
# memory, nothing is written to disk, and the device removes itself from the
# tailnet after going offline. Sign in each boot with `tsup`.
{ config, lib, ... }:

let
  cfg = config.ashfall.tailscale;
  inherit (lib) mkOption mkEnableOption mkIf types optional;
in
{
  options.ashfall.tailscale = {
    enable = mkEnableOption "Tailscale";

    ephemeral = mkOption {
      type = types.bool;
      default = true;
      description = "Keep Tailscale state in memory only (ephemeral node).";
    };

    trustInterface = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open all ports to other devices on your tailnet (firewall trusts
        tailscale0). Off by default: only outgoing connections work and the
        tailnet is treated like any other network.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.tailscale.enable = true;
    services.tailscale.extraDaemonFlags = optional cfg.ephemeral "--state=mem:";
    networking.firewall.trustedInterfaces = optional cfg.trustInterface "tailscale0";
    networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

    # Without ephemeral mode, keep the login so the node stays the same device
    ashfall.persist.directories = optional (!cfg.ephemeral) "/var/lib/tailscale";

    programs.bash.shellAliases.tsup = "sudo tailscale up";
  };
}
