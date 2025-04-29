{ callPackage, ... }:
let
  misc = callPackage ./misc { };
  security = callPackage ./security { };
  web = callPackage ./web { };
  homeAutomation = callPackage ./home-automation { };
in misc // security // homeAutomation // web
