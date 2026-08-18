# Patched packages, usable from a NixOS config, a Home Manager config, or an ad
# hoc `nix run` on another machine. Nothing here needs a GPU to build.
final: prev:

{
  ollama-patched = import ./ollama.nix prev.ollama;
}
// prev.lib.optionalAttrs (prev ? ollama-cuda) {
  ollama-cuda-patched = import ./ollama.nix prev.ollama-cuda;
}
// prev.lib.optionalAttrs (prev ? home-assistant) {
  home-assistant-patched = import ./home-assistant.nix prev.home-assistant;
}
