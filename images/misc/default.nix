{ callPackage, ... }:
{
	hello = callPackage ./hello {};
	fava = callPackage ./fava {};
}