{ callPackage, ... }:
{
	hello = callPackage ./hello {};
	fava = callPackage ./fava {};
	homepage-dashboard = ./homepage-dashboard {};
}