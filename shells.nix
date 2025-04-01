pkgs: with pkgs; {
  definitely-typed = mkShellNoCC {
    buildInputs = [
      dprint
      nodejs
      pnpm
    ];
  };
  yarn = mkShellNoCC {
    buildInputs = [
      nodejs
      yarn
    ];
  };
}
