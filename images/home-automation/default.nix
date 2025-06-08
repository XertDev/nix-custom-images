{ callPackage, ... }: {
  zigbee2mqtt = callPackage ./zigbee2mqtt { };
  home-assistant = callPackage ./home-assistant { };
}
