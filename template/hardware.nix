# Placeholder. The installer replaces this with the output of:
#   nixos-generate-config --no-filesystems --show-hardware-config
# (filesystems come from ashfall's disk layout, not from here)
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
