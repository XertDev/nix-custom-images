{
	description = "Custom OCI images with internal based configuration";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
		flake-parts = {
			url = "github:hercules-ci/flake-parts";
			inputs = {
				nixpkgs-lib.follows = "nixpkgs";
			};
		};
    flake-utils.url = "github:numtide/flake-utils";

		nix-snapshotter = {
			url = "github:pdtpartners/nix-snapshotter";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		search = {
			url = "github:NuschtOS/search";
			inputs = {
				flake-utils.follows = "flake-utils";
				nixpkgs.follows = "nixpkgs";
			};
		};
	};

	outputs = inputs@{ nixpkgs, flake-parts, ... }:
		flake-parts.lib.mkFlake { inherit inputs; }	{
			imports = [
				./flake-modules
			];

			systems = [
				"x86_64-linux"
			];

			perSystem = { inputs', system, pkgs, lib, ... }:
			let
        internal = import ./internal { inherit lib; inherit pkgs; };
        inherit (internal) mkImage;

        ignoredAttributes = [
          "extend"
          "override"
          "overrideScope"
          "overrideDerivation"
        ];

        repoUrl = "https://github.com/XertDev/nix-custom-images";

        callPackage = pkgs.lib.callPackageWith (pkgs // {
          inherit callPackage;
          inherit mkImage;
        });

        imageDefinitions = builtins.mapAttrs (
            k: v: builtins.removeAttrs v ignoredAttributes
          ) (builtins.removeAttrs (callPackage ./images { }) ignoredAttributes);

        images = builtins.mapAttrs (key: val:
            builtins.mapAttrs (key: val: val.builder) val
          ) imageDefinitions;
        image-build-check = pkgs.callPackage ./tests { inherit images; };

        imageOptions = builtins.mapAttrs (key: val:
					builtins.mapAttrs (key: val: val.options) val
				) imageDefinitions;

				scopes = lib.lists.flatten (
					map (val:
						lib.attrsets.mapAttrsToList (k: v: {
						  name = "${val}-${k}";
							optionsPrefix = "${val}.${k}";
							modules = [
								{ options = v; }
							];
							urlPrefix = "${repoUrl}/tree/master";
						}) imageOptions."${val}"
					) (builtins.attrNames imageOptions)
				);
      in
      {
				inherit images;
				checks = {
					inherit image-build-check;
				};
				packages = {
					documentation = inputs'.search.packages.mkMultiSearch {
						title = "Custom images";
						inherit scopes;
					};
				};
			};
		};
}