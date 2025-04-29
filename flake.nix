{
  description = "My Nix environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { nixpkgs, home-manager, ... }:
    let
      pkgsX86 = import nixpkgs { system = "x86_64-linux"; };
      pkgsArm = import nixpkgs { system = "aarch64-darwin"; };
    in
    {
      packages = home-manager.packages; # Support bootstrapping Home Manager.
      homeConfigurations = {
        "sam" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsX86;
          modules = [ ./desktop/home-manager/home.nix ];
        };
        "samueles" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsArm;
          modules = [ ./macbook/home-manager/home.nix ];
        };
      };
      devShells =
        let
          shells =
            pkgs:
            with pkgs;
            (import ./shells.nix pkgs)
            // {
              default = mkShellNoCC {
                buildInputs = [
                  nixfmt-rfc-style
                  python3
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
