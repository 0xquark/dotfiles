{
  description = "drquark's delorean";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Zen browser (not in nixpkgs)
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs"; # one nixpkgs for everything
    };
    # Theme Engine (Stylix branch version must match the nixos release (26.05))
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Spotify, themable
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Claude
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes, the agent behind Joi (wallace/joi). It keeps its own nixpkgs,
    # since its Python set is locked against it.
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # Weekly index of every program in nixpkgs, for comma and "command not found"
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Lazarus, the throwaway VM for HTB and untrusted code
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      home-manager,
      stylix,
      microvm,
      ...
    }@inputs:
    {
      # Lazarus: a throwaway VM that reads the host's /nix/store, so it has the
      # basement tools without a download. Start it with `laz`.
      nixosConfigurations.lazarus = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          microvm.nixosModules.microvm
          ./hosts/lazarus/configuration.nix
        ];
      };
      # The same VM with a disk, for `laz -p 3d`
      nixosConfigurations.lazarus-kept = self.nixosConfigurations.lazarus.extendModules {
        modules = [ ./hosts/lazarus/kept.nix ];
      };
      packages.x86_64-linux.lazarus = self.nixosConfigurations.lazarus.config.microvm.declaredRunner;
      packages.x86_64-linux.lazarus-kept =
        self.nixosConfigurations.lazarus-kept.config.microvm.declaredRunner;

      # Named after your hostname, so `nixos-rebuild --flake ~/nixos` finds it
      nixosConfigurations.delorean = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; }; # lets any module use inputs.*
        modules = [
          ./hosts/framework/configuration.nix
          ./hosts/framework/theme.nix
          ./hosts/framework/themes.nix # extra themes to switch to
          nixos-hardware.nixosModules.framework-intel-core-ultra-series3
          stylix.nixosModules.stylix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak"; # don't fail on existing dotfiles
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.drquark =
              { pkgs, ... }:
              {
                imports = [
                  ./home # the desktop and apps
                  ./wallace # Joi, the other characters, and dictation
                ];
                # Joi's battery tool switches the charge limit with the bar's script
                wallace.joi.chargeLimitCommand = "${import ./home/charge-limit.nix { inherit pkgs; }}";
              };
          }
        ];
      };

      # `nix fmt` tidies every .nix file in the repo
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
