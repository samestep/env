pkgs: with pkgs; {
  definitely-typed = mkShellNoCC {
    buildInputs = [
      dprint
      nodejs
      pnpm
    ];
  };
  pnpm = mkShellNoCC {
    buildInputs = [
      nodejs
      pnpm
    ];
  };
  vscode = mkShellNoCC {
    buildInputs = [
      clang
      krb5
      llvm
      nodejs_20
      python3
    ];
  };
  yarn = mkShellNoCC {
    buildInputs = [
      nodejs
      yarn
    ];
  };
}
