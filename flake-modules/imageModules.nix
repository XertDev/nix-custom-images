{ lib, flake-parts-lib, ... }:
let
  inherit (flake-parts-lib) mkTransposedPerSystemModule;
  inherit (lib) mkOption types;

  variantType = types.lazyAttrsOf (types.functionTo types.package);
in mkTransposedPerSystemModule {
  name = "images";
  option = mkOption {
    type = types.lazyAttrsOf variantType;
    description = ''
      OCI compatible image's functors
    '';
    default = { };
  };
  file = ./imageModules.nix;
}
