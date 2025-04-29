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
		git-hooks-nix = {
			url = "github:cachix/git-hooks.nix";
			inputs = {
				nixpkgs.follows = "nixpkgs";
			};
		};

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
        inputs.git-hooks-nix.flakeModule

				./flake-modules
			];

			systems = [
				"x86_64-linux"
			];

			perSystem = { config, inputs', system, pkgs, lib, ... }:
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
        pre-commit.settings.hooks = {
          deadnix.enable = true;
          nixfmt-classic.enable = true;
        };
        devShells.default = pkgs.mkShell {
          shellHook = ''
	          ${config.pre-commit.installationScript}
          '';
        };

				inherit images;
				checks = {
					inherit image-build-check;
				};
				packages = {
					docs = inputs'.search.packages.mkMultiSearch {
						title = "Custom images";
						inherit scopes;
					};
					githubDocs = inputs'.search.packages.mkMultiSearch {
						title = "Custom images";
						baseHref = "/nix-custom-images/";
						inherit scopes;
					};
				};
			};
		};
}