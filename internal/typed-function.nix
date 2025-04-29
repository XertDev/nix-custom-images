{ lib, ... }:
definition: args:
let
  options = definition.options or { };
  function = definition.function;

  evaluatedConfig = lib.evalModules {
    modules = [ { inherit options; } args { config._module.check = true; } ];
  };
in function { inherit (evaluatedConfig) config; }
