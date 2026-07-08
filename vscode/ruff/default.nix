# The Ruff VS Code extension, built from source (nixpkgs ships the prebuilt
# Marketplace VSIX) so we can patch its TypeScript rather than minified JS.
#
# The patch drops the modal error the extension pops when its interpreter probe
# throws -- which happens in non-Python projects where direnv has leaked the Nix
# SDK's DEVELOPER_DIR and thereby broken Apple's /usr/bin/python3 shim. The
# extension already falls back to the bundled ruff and works, so we keep only
# the log line.
#
# To bump `version`, refresh both hashes:
#   nix flake prefetch github:astral-sh/ruff-vscode/<version>        # -> hash
#   nix run nixpkgs#prefetch-npm-deps -- <checkout>/package-lock.json  # -> npmDepsHash
# and re-check that no-popup.patch still applies (it fails loudly if not).
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  ruff,
}:

buildNpmPackage rec {
  pname = "vscode-extension-charliermarsh-ruff";
  version = "2026.56.0";

  src = fetchFromGitHub {
    owner = "astral-sh";
    repo = "ruff-vscode";
    rev = version;
    hash = "sha256-96aITdErMnwJmhMmu2MUSVDu1kOavizUZWYQKFuIR6g=";
  };

  npmDepsHash = "sha256-sHv1J1O1q64161ImBOja8m6xzH+vmk3gsYkQc3YYNk8=";

  patches = [ ./no-popup.patch ];

  # Match upstream's `npm ci --ignore-scripts`; the deps are pure JS.
  npmFlags = [ "--ignore-scripts" ];

  # `npm run package` == webpack --mode production -> dist/extension.js
  npmBuildScript = "package";

  installPhase = ''
    runHook preInstall

    ext="$out/share/vscode/extensions/charliermarsh.ruff"
    mkdir -p "$ext/bundled"

    cp package.json icon.png README.md CHANGELOG.md LICENSE "$ext/"
    cp -r dist "$ext/dist"
    cp -r bundled/tool "$ext/bundled/tool"

    # The native server (ruff.nativeServer, the default) runs this ruff binary
    # directly. We skip the rest of bundled/libs -- the deprecated ruff-lsp
    # Python stack, only used when ruff.nativeServer = "off".
    mkdir -p "$ext/bundled/libs/bin"
    ln -s ${lib.getExe ruff} "$ext/bundled/libs/bin/ruff"

    runHook postInstall
  '';

  meta = {
    description = "Ruff VS Code extension, from source, with the spurious binary-lookup modal removed";
    homepage = "https://github.com/astral-sh/ruff-vscode";
    license = lib.licenses.mit;
  };
}
