{ callPackage, ... }:
let
  misc = callPackage ./misc { };
  security = callPackage ./security { };
  web = callPackage ./web { };
  homeAutomation = callPackage ./home-automation { };
  middleware = callPackage ./middleware { };
in misc // security // homeAutomation // web // middleware
