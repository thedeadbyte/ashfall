{
  description = "ashfall: a NixOS laptop that burns down to a clean system on every boot";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, impermanence, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      # Forks: change this to your repo so generated configs track your copy
      flakeRef = "github:thedeadbyte/ashfall";

      installer = pkgs.writeShellApplication {
        name = "ashfall-install";
        runtimeInputs = with pkgs; [ git mkpasswd util-linux coreutils gnugrep gnused gawk curl findutils ];
        text = ''
          ASHFALL_FLAKE="''${ASHFALL_FLAKE:-${flakeRef}}"
          DISKO="${disko.packages.${system}.disko}/bin/disko"
          STATE_VERSION="${lib.versions.majorMinor lib.version}"
        '' + builtins.readFile ./installer/install.sh;
      };
    in
    {
      # Import this in your own flake, then set ashfall.* options
      nixosModules.default = {
        imports = [
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
          home-manager.nixosModules.home-manager
          ./modules
        ];
      };

      # nix flake init -t github:thedeadbyte/ashfall
      templates.default = {
        path = ./template;
        description = "ashfall machine config";
      };

      # sudo nix run github:thedeadbyte/ashfall   (from the NixOS live USB)
      packages.${system} = {
        inherit installer;
        default = installer;
      };
      apps.${system}.default = {
        type = "app";
        program = "${installer}/bin/ashfall-install";
      };

      # Evaluated in CI / by `nix flake check` to keep the modules honest
      nixosConfigurations.example = lib.nixosSystem {
        modules = [
          self.nixosModules.default
          ./template/hardware.nix
          ./template/configuration.nix
        ];
      };
    };
}
