{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    supportSnapshotter = true;

    options = with lib; { package = mkPackageOption pkgs "hello" { }; };

    image = { config, ... }:
      let
        initScript = pkgs.writeShellApplication {
          name = "hello-entrypoint";
          runtimeInputs = [ config.package ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            #Running preStart hook
            ${config.preStart}

            hello
          '';
        };
      in {
        name = "hello";
        tag = "latest";
        config = { Cmd = [ (pkgs.lib.meta.getExe initScript) ]; };
      };
  };
}
