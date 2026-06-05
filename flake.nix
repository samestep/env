{
  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    npc = {
      url = "github:samestep/npc";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    moss = {
      url = "github:moss-lang/moss";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
  };
  outputs =
    {
      self,
      nixpkgs-stable,
      nixpkgs,
      home-manager,
      nix-index-database,
      rust-overlay,
      npc,
      moss,
    }:
    {
      packages = {
        x86_64-linux.home-manager = home-manager.packages.x86_64-linux.default;
        aarch64-linux.home-manager = home-manager.packages.aarch64-linux.default;
        aarch64-darwin.home-manager = home-manager.packages.aarch64-darwin.default;
      };
      nixosConfigurations = {
        "nixos" = nixpkgs-stable.lib.nixosSystem {
          modules = [ ./nixos/nixos/configuration.nix ];
        };
      };
      homeConfigurations =
        let
          commaOverlay = final: prev: {
            comma = final.symlinkJoin {
              name = "comma";
              paths = [
                (nix-index-database.packages.${final.stdenv.hostPlatform.system}.comma-with-db.override {
                  # Have comma use Nix from PATH, to avoid Determinate warnings.
                  comma = prev.comma.override {
                    nix = final.symlinkJoin {
                      name = "nix";
                      paths = [
                        (final.writeShellScriptBin "nix" ''
                          exec nix "$@"
                        '')
                        (final.writeShellScriptBin "nix-env" ''
                          exec nix-env "$@"
                        '')
                      ];
                      meta.mainProgram = "nix";
                    };
                  };
                })
              ];
              nativeBuildInputs = [ final.makeWrapper ];
              postBuild = ''
                for cmd in , comma; do
                  wrapProgram $out/bin/$cmd \
                    --unset NIX_PATH \
                    --set COMMA_CACHING 1 \
                    --set COMMA_NIXPKGS_FLAKE path:${nixpkgs}
                done
              '';
            };
          };
        in
        {
          "sam" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [
                commaOverlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./nixos/home-manager/home.nix
            ];
          };
          "samueles" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-darwin";
              overlays = [
                commaOverlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./macos/home-manager/home.nix
            ];
          };
          "agent-amd64" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [
                commaOverlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./docker-x86/home-manager/home.nix
            ];
          };
          "agent-arm64" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-linux";
              overlays = [
                commaOverlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./docker-arm/home-manager/home.nix
            ];
          };
          "admin" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-darwin";
              overlays = [
                commaOverlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./tart/home-manager/home.nix
            ];
          };
        };
      devShells =
        let
          shells =
            pkgs:
            (import ./shells.nix { inherit pkgs; })
            // {
              default = pkgs.mkShellNoCC {
                packages = [
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
          aarch64-linux = shells (
            import nixpkgs {
              system = "aarch64-linux";
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
