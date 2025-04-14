{ pkgs, lib, images, ... }:
let
	ignoredAttributes = [
    "extend"
    "override"
    "overrideScope"
    "overrideDerivation"
  ];

	onlyImages = builtins.mapAttrs (k: v: builtins.removeAttrs v ignoredAttributes) (builtins.removeAttrs images ignoredAttributes);

	imageNames = builtins.attrNames onlyImages;
	subtypeNames = builtins.listToAttrs (
		map (val: {
			name = val;
			value = (builtins.attrNames (
				builtins.removeAttrs images."${val}" ignoredAttributes
			));
		}) imageNames
	);

	subtypesCount = let
			perSubtypeCount = builtins.mapAttrs (k: v: builtins.length v) subtypeNames;
		in lib.attrsets.foldlAttrs (acc: _: v: acc + v) 0 perSubtypeCount;

	subtypeFunctions = lib.lists.flatten (
		map (val: (
			lib.attrsets.mapAttrsToList (k: v: { path = [val k]; args = {}; } ) onlyImages.${val}
		)) imageNames
	);
in
pkgs.runCommand "image-build-check" {
} ''
		echo "Discovered ${builtins.toString (builtins.length imageNames)} images"
		echo "Total subtypes: ${builtins.toString subtypesCount}"

		${
			lib.strings.concatStringsSep "\n" (
				map (val:
					''
						echo "${lib.concatStringsSep "." val.path} -> ${(lib.attrsets.getAttrFromPath val.path images) val.args}"
					''
				) subtypeFunctions
			)
		}

		touch $out
''