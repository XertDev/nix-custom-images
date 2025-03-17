{ lib, pkgs, ... }:
let
	mkTypedFunction = import ./typed-function.nix { inherit lib; };
in
definition: args:
	let
		userOptions = definition.options;
		defaultOptions = {
		};

		functionDef = {
			options = defaultOptions // userOptions;
			function = definition.image;
		};

		defaultArguments = {};

		evaluatedImageDefinition = mkTypedFunction functionDef args;
	in pkgs.dockerTools.streamLayeredImage (defaultArguments // evaluatedImageDefinition)