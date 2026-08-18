{
  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    # nixos-unstable rather than nixpkgs-unstable: it gates on the NixOS test
    # suite, and it runs ahead often enough to matter (it carried ollama 0.32.13
    # while nixpkgs-unstable was still two days back on 0.32.7).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
    npb = {
      url = "github:samestep/npb";
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
      npb,
      moss,
    }:
    {
      # Patched ollama and Home Assistant, so the same definitions can be used
      # from a NixOS config, a Home Manager config, another machine's `nix run`,
      # or a Mac. See packages/prefix-cache-findings.md for what the patches do.
      overlays.default = import ./packages/overlay.nix;

      packages =
        let
          patched =
            system:
            let
              pkgs = import nixpkgs {
                inherit system;
                config.allowUnfree = true;
                overlays = [ (import ./packages/overlay.nix) ];
              };
            in
            {
              inherit (pkgs) ollama-patched;
            }
            // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              inherit (pkgs) ollama-cuda-patched home-assistant-patched;
            };
        in
        {
          x86_64-linux = {
            home-manager = home-manager.packages.x86_64-linux.default;
          }
          // patched "x86_64-linux";
          aarch64-linux = {
            home-manager = home-manager.packages.aarch64-linux.default;
          }
          // patched "aarch64-linux";
          aarch64-darwin = {
            home-manager = home-manager.packages.aarch64-darwin.default;
          }
          // patched "aarch64-darwin";
        };
      nixosConfigurations = {
        "nixos" = nixpkgs-stable.lib.nixosSystem {
          # So the host can take individual packages from unstable.
          specialArgs.nixpkgsUnstable = nixpkgs;
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
                npb.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./modules/base.nix
              ./modules/safe.nix
              ./modules/vscode.nix
              ./modules/vscode-linux.nix
              ./nixos/home-manager/home.nix
            ];
          };
          "samueles" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-darwin";
              overlays = [
                commaOverlay
                npb.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./modules/base.nix
              ./modules/safe.nix
              ./modules/vscode.nix
              ./modules/vscode-darwin.nix
              ./macos/home-manager/home.nix
            ];
          };
          "agent-amd64" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [
                commaOverlay
                npb.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./modules/base.nix
              ./modules/yolo.nix
              ./sandbox-amd64/home-manager/home.nix
            ];
          };
          "admin@ubuntu" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-linux";
              overlays = [
                commaOverlay
                npb.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./modules/base.nix
              ./modules/yolo.nix
              ./ubuntu/home-manager/home.nix
            ];
          };
          "admin@Manageds-Virtual-Machine" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "aarch64-darwin";
              overlays = [
                commaOverlay
                npb.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./modules/base.nix
              ./modules/yolo.nix
              ./tahoe-vanilla/home-manager/home.nix
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
