pkgs: with pkgs; {
  definitely-typed = mkShellNoCC {
    buildInputs = [
      dprint
      nodejs
      pnpm
    ];
  };
}
