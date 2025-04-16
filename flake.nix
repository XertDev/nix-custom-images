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

		nix-snapshotter = {
			url = "github:pdtpartners/nix-snapshotter";
			inputs.nixpkgs.follows = "nixpkgs";
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

        callPackage = pkgs.lib.callPackageWith (pkgs // {
          inherit callPackage;
          inherit mkImage;
        });

        imageDefinitions = callPackage ./images { };
        images = builtins.mapAttrs (key: val:
            builtins.mapAttrs (key: val: if val ? builder then val.builder else val) val
          ) imageDefinitions;
        image-build-check = pkgs.callPackage ./tests { inherit images; };
      in
      {
				inherit images;
				checks = {
					inherit image-build-check;
				};
			};
		};
}