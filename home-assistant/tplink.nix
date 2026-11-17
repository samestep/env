{ pkgs, ... }:

{
  services.home-assistant.package = pkgs.home-assistant.override {
    packageOverrides = _: prev: {
      python-kasa = prev.python-kasa.overridePythonAttrs (old: {
        # EP10 plugs can time out on batched refresh commands even when each
        # command succeeds separately. Split their status refreshes into
        # individual commands; control requests and other models keep their
        # existing behavior.
        patches = (old.patches or [ ]) ++ [ ./python-kasa-ep10-refresh.patch ];
        # This EP10 test assumes the original batched request count.
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_initial_update_no_emeter[EP10"
        ];
      });
    };
  };
}
