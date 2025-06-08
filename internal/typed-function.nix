{ lib, ... }:
definition: args:
let
  optionsModule = definition.optionsModule or { };
  function = definition.function;

  evaluatedConfig = lib.evalModules {
    modules = [ optionsModule args { config._module.check = true; } ];
  };
in function { inherit (evaluatedConfig) config; }
