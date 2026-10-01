{
  description = "My machine, built on ashfall";

  inputs = {
    ashfall.url = "github:thedeadbyte/ashfall";
    nixpkgs.follows = "ashfall/nixpkgs";
  };

  outputs = { ashfall, nixpkgs, ... }: {
    # The name must match networking.hostName in configuration.nix
    nixosConfigurations.ashfall = nixpkgs.lib.nixosSystem {
      modules = [
        ashfall.nixosModules.default
        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
