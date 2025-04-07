{ callPackage, ... }:
let
	misc = callPackage ./misc {};
	security = callPackage ./security {};
	homeAutomation = callPackage ./home-automation {};
in
	misc // security // homeAutomation