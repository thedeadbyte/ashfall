{
  description = "My machines, built on ashfall";

  inputs = {
    ashfall.url = "github:thedeadbyte/ashfall";
    nixpkgs.follows = "ashfall/nixpkgs";
  };

  outputs = { ashfall, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      # Every folder in hosts/ is one machine, and its name is the hostname.
      # Add a machine with: nix run github:thedeadbyte/ashfall -- --add-host .
      hosts = lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts);
    in
    {
      nixosConfigurations = lib.mapAttrs (name: _: lib.nixosSystem {
        modules = [
          ashfall.nixosModules.default
          ./hosts/common.nix
          (./hosts + "/${name}")
          { networking.hostName = name; }
        ];
      }) hosts;
    };
}
