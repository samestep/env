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
          # Each patched package comes from the same nixpkgs the NixOS host takes
          # it from, because the patches are version-specific: the Silero one
          # does not apply to Home Assistant 2026.8.2 in unstable, only to the
          # 2026.5.4 in stable. A development instance on a different version
          # would not tell us anything transferable.
          with-overlay =
            input: system:
            import input {
              inherit system;
              config.allowUnfree = true;
              overlays = [ (import ./packages/overlay.nix) ];
            };
          patched =
            system:
            let
              unstable = with-overlay nixpkgs system; # ollama: host takes it from here
              stable = with-overlay nixpkgs-stable system; # home-assistant: ditto
            in
            {
              inherit (unstable) ollama-patched;
            }
            // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "linux" system) {
              inherit (unstable) ollama-cuda-patched;
              inherit (stable) home-assistant-patched;

              # A Home Assistant that can run standalone, for the development
              # instance in the agent VM. The NixOS module normally derives
              # extraComponents from the configuration; running `hass` straight
              # out of the package gets only the defaults, and the ollama config
              # flow then fails with "Invalid handler specified".
              #
              # Same components as the real machine, so the two behave alike.
              # Runnable wrapper: `nix run .#hass-dev -- -c ~/ha-dev`. The
              # component dependencies live in passthru.pythonPath rather than in
              # the package, which is why the NixOS module sets
              # environment.PYTHONPATH from it; running `hass` directly without
              # that gets "Invalid handler specified" for ollama.
              hass-dev =
                let
                  ha = patched-for system;
                in
                stable.writeShellScriptBin "hass-dev" ''
                  export PYTHONPATH=${ha.pythonPath}
                  exec ${ha}/bin/hass "$@"
                '';

              home-assistant-dev = patched-for system;
            };

          patched-for =
            system:
            let
              stable = with-overlay nixpkgs-stable system;
            in
            import ./packages/home-assistant.nix (
              stable.home-assistant.override {
                extraComponents = [
                  # The NixOS module always adds these and running `hass` outside
                  # the module does not. Without "frontend" the hass_frontend
                  # module is missing, frontend setup fails, and Home Assistant
                  # drops into recovery mode -- which ignores configuration.yaml
                  # entirely, so nothing below loads and the failure looks
                  # unrelated to the frontend.
                  "application_credentials"
                  "frontend"
                  "hardware"
                  "logger"
                  "network"
                  "system_health"
                  "automation"
                  "person"
                  "scene"
                  "script"
                  "zone"

                  # Same as the real machine.
                  "assist_pipeline"
                  "demo"
                  "esphome"
                  "met"
                  "ollama"
                  "radio_browser"
                  "wyoming"
                ];
              }
            );
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
