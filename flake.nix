{
  description = "My Nix environment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      # https://github.com/nix-community/nixGL/pull/195
      url = "github:jinluchang/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      nixgl,
      rust-overlay,
    }:
    {
      packages = home-manager.packages; # Support bootstrapping Home Manager.
      homeConfigurations = {
        "sam" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "x86_64-linux"; };
          modules = [ ./nixos/home-manager/home.nix ];
        };
        "samueles" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "aarch64-darwin"; };
          modules = [ ./macos/home-manager/home.nix ];
          extraSpecialArgs = { inherit nix-darwin; };
        };
        "saestep" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ nixgl.overlay ];
          };
          modules = [ ./ubuntu/home-manager/home.nix ];
        };
      };
      darwinConfigurations."gs21624" = nix-darwin.lib.darwinSystem {
        modules = [ ./macos/nix-darwin/configuration.nix ];
      };
      devShells =
        let
          shells =
            pkgs:
            (import ./shells.nix { inherit pkgs; })
            // {
              default = pkgs.mkShellNoCC {
                buildInputs = [
                  pkgs.nixfmt
                  pkgs.python3
                ];
              };
            };
        in
        {
          x86_64-linux = shells (
            import nixpkgs {
              system = "x86_64-linux";
              overlays = [ (import rust-overlay) ];
            }
          );
          aarch64-darwin = shells (
            import nixpkgs {
              system = "aarch64-darwin";
              overlays = [ (import rust-overlay) ];
            }
          );
        };
    };
}
