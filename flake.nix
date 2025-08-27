{
  description = "My Nix environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      # https://github.com/nix-community/nixGL/pull/195
      url = "github:jinluchang/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixgl,
      fenix,
    }:
    let
      pkgsX86 = import nixpkgs { system = "x86_64-linux"; };
      pkgsArm = import nixpkgs { system = "aarch64-darwin"; };
      pkgsNixGL = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ nixgl.overlay ];
      };
    in
    {
      packages = home-manager.packages; # Support bootstrapping Home Manager.
      homeConfigurations = {
        "sam" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsX86;
          modules = [ ./nixos/home-manager/home.nix ];
        };
        "samueles" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsArm;
          modules = [ ./macos/home-manager/home.nix ];
        };
        "saestep" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsNixGL;
          modules = [ ./ubuntu/home-manager/home.nix ];
        };
      };
      devShells =
        let
          shells =
            pkgs:
            (import ./shells.nix { inherit pkgs fenix; })
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
          x86_64-linux = shells pkgsX86;
          aarch64-darwin = shells pkgsArm;
        };
    };
}
