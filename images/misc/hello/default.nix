{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    supportSnapshotter = true;

    options = with lib; { package = mkPackageOption pkgs "hello" { }; };

    image = { config, ... }: {
      name = "hello";
      tag = "latest";
      config = { Cmd = [ (pkgs.lib.meta.getExe config.package) ]; };
    };
  };
}
