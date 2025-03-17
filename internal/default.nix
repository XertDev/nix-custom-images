{ lib, pkgs, ... }:
{
	mkImage = import ./image-definition.nix { inherit lib; inherit pkgs; };
}