pkgs: with pkgs; {
  definitely-typed = mkShellNoCC {
    buildInputs = [
      dprint
      nodejs
      pnpm
    ];
  };
  node = mkShellNoCC {
    buildInputs = [
      nodejs
    ];
  };
  pnpm = mkShellNoCC {
    buildInputs = [
      nodejs
      pnpm
    ];
  };
  uv = mkShellNoCC {
    buildInputs = [
      uv
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
