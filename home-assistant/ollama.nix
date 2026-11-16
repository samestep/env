{ pkgs, ... }:

{
  services.ollama = {
    enable = true;
    # Compile CUDA kernels only for this host's RTX 5880 Ada.
    package = pkgs.ollama-cuda.override { cudaArches = [ "sm_89" ]; };
    host = "127.0.0.1";
    # Use the publisher's 1.5 weights; ollama's ornith:35b tag is still 1.0.
    loadModels = [ "hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q4_K_M" ];
    environmentVariables = {
      # Leave GPU memory for Qwen ASR; HA can override context per request.
      OLLAMA_CONTEXT_LENGTH = "8192";
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_KEEP_ALIVE = "-1";
      OLLAMA_FLASH_ATTENTION = "1";
    };
  };
}
