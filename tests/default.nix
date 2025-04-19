{ pkgs, lib, images, ... }:
let

	imageNames = builtins.attrNames images;
	subtypeNames = builtins.listToAttrs (
		map (val: {
			name = val;
			value = (builtins.attrNames images."${val}");
		}) imageNames
	);

	subtypesCount = let
			perSubtypeCount = builtins.mapAttrs (k: v: builtins.length v) subtypeNames;
		in lib.attrsets.foldlAttrs (acc: _: v: acc + v) 0 perSubtypeCount;

	subtypeFunctions = lib.lists.flatten (
		map (val: (
			lib.attrsets.mapAttrsToList (k: v: { path = [val k]; args = {}; }) images.${val}
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
						echo "${lib.strings.concatStringsSep "." val.path} -> ${(lib.attrsets.getAttrFromPath val.path images) val.args}"
					''
				) subtypeFunctions
			)
		}

		touch $out
''