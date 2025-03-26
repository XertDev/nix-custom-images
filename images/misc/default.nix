{ callPackage, ... }:
{
	hello = callPackage ./hello {};
	fava = callPackage ./fava {};
	homepage-dashboard = callPackage ./homepage-dashboard {};
}