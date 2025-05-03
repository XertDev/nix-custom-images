{ lib, pkgs, ... }:
let mkTypedFunction = import ./typed-function.nix { inherit lib; };
in definition:
let
  userOptions = definition.options;
  defaultOptions = with lib; {
    useSnapshotter = mkOption {
      default = false;
      type = types.bool;
      description = "Should image use paths directly from store";
    };

    tag = mkOption {
      type = types.nullOr types.str;
      default = null;
      visible = false;
      description = "Image tag override";
    };
  };

  functionDef = {
    options = defaultOptions // userOptions;
    function = { config }: {
      resolvedImage = definition.image { inherit config; };
      inherit config;
    };
  };
in {
  inherit (functionDef) options;
  builder = args:
    let
      evaluatedImageDefinition = mkTypedFunction functionDef args;
      config = evaluatedImageDefinition.config;

      supportSnapshotter =
        lib.attrsets.attrByPath [ "supportSnapshotter" ] false definition;
      useSnapshotter = assert lib.asserts.assertMsg
        (!config.useSnapshotter || supportSnapshotter)
        ''Option "useSnapshotter" is not supported for selected image'';
        config.useSnapshotter;

      imageDefinition = evaluatedImageDefinition.resolvedImage
        // lib.attrsets.optionalAttrs (config.tag != null) {
          inherit (config) tag;
        };

      builder = if useSnapshotter then
        pkgs.nix-snapshotter.buildImage
      else
        pkgs.dockerTools.streamLayeredImage;
    in builder imageDefinition;
}

