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

    preStart = mkOption {
      type = with types; coercedTo (listOf str) (concatStringsSep "\n") lines;
      default = "";
      visible = false;
      description = "Commands called before main application start";
    };

    tag = mkOption {
      type = types.nullOr types.str;
      default = null;
      visible = false;
      description = "Image tag override";
    };

    name = mkOption {
      type = types.nullOr types.str;
      default = null;
      visible = false;
      description = "Image name override";
    };
  };

  tests = map (test: {
    inherit (test) name config;
    script = pkgs.writeShellScript "" test.script;
  }) (lib.optionals (definition ? tests) definition.tests);

  defaultBuildArgs = lib.optionalAttrs (definition ? defaultBuildArgs)
    definition.defaultBuildArgs;

  optionsModule = if (builtins.isFunction userOptions) then
    { config, ... }: {
      options = defaultOptions // (userOptions { inherit config; });
    }
  else {
    options = defaultOptions // userOptions;
  };

  functionDef = {
    inherit optionsModule;
    function = { config }: {
      resolvedImage = definition.image { inherit config; };
      inherit config;
    };
  };
in {
  inherit optionsModule;
  inherit tests defaultBuildArgs;
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
        } // lib.attrsets.optionalAttrs (config.name != null) {
          inherit (config) name;
        };

      builder = if useSnapshotter then
        pkgs.nix-snapshotter.buildImage
      else
        pkgs.dockerTools.streamLayeredImage;
    in builder imageDefinition;
}

