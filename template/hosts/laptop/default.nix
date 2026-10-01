# This machine (laptop) only. Settings shared by all your machines are in
# ../common.nix; the hostname is this folder's name.
{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  # Set when this machine was installed. Don't change them afterwards.
  ashfall.disk.device = "/dev/nvme0n1"; # erased by the installer
  ashfall.disk.swapSize = "8G";         # null for no swapfile

  # Settings for this machine only go here, for example:
  #   ashfall.wipeHome = false;
  #   environment.systemPackages = with pkgs; [ ];

  system.stateVersion = "26.05"; # Do not change after install
}
