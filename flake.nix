{
  description = "drquark's Framework 13 Pro";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";   # one nixpkgs for everything
    };
  };

  outputs = { nixpkgs, nixos-hardware, home-manager, ... }@inputs: {
    # Named after your hostname, so `nixos-rebuild --flake ~/nixos` finds it
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };     # lets any module use inputs.*
      modules = [
        ./hosts/framework/configuration.nix
        nixos-hardware.nixosModules.framework-intel-core-ultra-series3
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";  # don't fail on existing dotfiles
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.drquark = import ./home;
        }
      ];
    };
  };
}
