pkgs: with pkgs; {
  pnpm = mkShellNoCC {
    buildInputs = [
      nodejs
      pnpm
    ];
  };
}
