{ lib, pkgs, ... }:
let
	mkTypedFunction = import ./typed-function.nix { inherit lib; };
in
definition: args:
	let
		userOptions = definition.options;
		defaultOptions = with lib; {
			useSnapshotter = mkOption {
				default = false;
				type = types.bool;
				description = "Should image use paths directly from store";
			};
		};

		functionDef = {
			options = defaultOptions // userOptions;
			function = { config }: {
				resolvedImage = definition.image { inherit config; };
				inherit (config)
					useSnapshotter;
			};
		};

		evaluatedImageDefinition = mkTypedFunction functionDef args;

		supportSnapshotter = lib.attrsets.attrByPath ["supportSnapshotter"] false definition;
		useSnapshotter = assert
			lib.asserts.assertMsg (!evaluatedImageDefinition.useSnapshotter || supportSnapshotter)
			"Option \"useSnapshotter\" is not supported for selected image";
			evaluatedImageDefinition.useSnapshotter;

		builder = if useSnapshotter
			then pkgs.nix-snapshotter.buildImage
			else pkgs.dockerTools.streamLayeredImage;
	in builder (evaluatedImageDefinition.resolvedImage)