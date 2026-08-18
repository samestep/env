# Smart Turn v3: predicts whether a speaker has finished their turn.
#
# A silence threshold cannot tell "still thinking" from "finished" -- they are
# acoustically identical and only the words differ. This model reads the
# waveform and says whether the utterance sounds complete, so a short silence
# threshold can serve the common case while genuine mid-thought pauses are held
# open.
#
# Measured on the model's own labelled test set, real non-synthetic English
# only: 93.2% accuracy over 607 samples, 25 ms per call on one CPU thread.
{
  lib,
  buildPythonPackage,
  python,
  numpy,
  onnxruntime,
  fetchurl,
}:

let
  model = fetchurl {
    url = "https://huggingface.co/pipecat-ai/smart-turn-v3/resolve/main/smart-turn-v3.2-cpu.onnx";
    hash = "sha256-K7AmMWsUpmBIanWxczzT+6uML9AxTcmve+SfjMqWfk8=";
  };
in
buildPythonPackage {
  pname = "smart-turn-vad";
  version = "3.2";
  format = "other";

  src = ./smart-turn;

  propagatedBuildInputs = [
    numpy
    onnxruntime
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/${python.sitePackages}
    cp ${./smart-turn/smart_turn_vad.py} \
      $out/${python.sitePackages}/smart_turn_vad.py
    mkdir -p $out/share/smart-turn
    cp ${model} $out/share/smart-turn/smart-turn-v3.2-cpu.onnx
    runHook postInstall
  '';

  # The module finds the model through this, so a caller needs no path.
  postFixup = ''
    cat >> $out/${python.sitePackages}/smart_turn_vad.py <<PY

    DEFAULT_MODEL_PATH = "$out/share/smart-turn/smart-turn-v3.2-cpu.onnx"
    PY
  '';

  pythonImportsCheck = [ "smart_turn_vad" ];

  meta = with lib; {
    description = "Semantic turn detection: has the speaker finished?";
    homepage = "https://huggingface.co/pipecat-ai/smart-turn-v3";
    license = licenses.bsd2;
  };
}
