{
  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
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
      nixgl,
      rust-overlay,
      npc,
      moss,
    }:
    {
      packages =
        let
          hm =
            system:
            let
              pkgs = import nixpkgs { inherit system; };
            in
            pkgs.writeShellApplication {
              name = "hm";
              runtimeInputs = [
                pkgs.nix-output-monitor
                home-manager.packages.${system}.default
              ];
              text = ''
                nom build "$HOME/.config/home-manager#homeConfigurations.$USER.activationPackage"
                home-manager switch
              '';
            };
        in
        {
          x86_64-linux.home-manager = home-manager.packages.x86_64-linux.default;
          aarch64-linux.home-manager = home-manager.packages.aarch64-linux.default;
          aarch64-darwin.home-manager = home-manager.packages.aarch64-darwin.default;
          x86_64-linux.hm = hm "x86_64-linux";
          aarch64-linux.hm = hm "aarch64-linux";
          aarch64-darwin.hm = hm "aarch64-darwin";
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
                nix-index-database.packages.${final.stdenv.hostPlatform.system}.comma-with-db
              ];
              nativeBuildInputs = [ final.makeWrapper ];
              postBuild = ''
                for cmd in , comma; do
                  wrapProgram $out/bin/$cmd \
                    --unset NIX_PATH \
                    --set COMMA_CACHING 1 \
                    --set COMMA_NIXPKGS_FLAKE nixpkgs/${nixpkgs.rev}
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
          "saestep" = home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [
                commaOverlay
                nixgl.overlay
                npc.overlays.default
                moss.overlays.default
              ];
            };
            modules = [
              nix-index-database.homeModules.default
              ./ubuntu/home-manager/home.nix
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
        };
      devShells =
        let
          shells =
            pkgs:
            (import ./shells.nix { inherit pkgs; })
            // {
              default = pkgs.mkShellNoCC {
                buildInputs = [
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
