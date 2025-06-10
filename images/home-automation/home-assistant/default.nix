{ pkgs, lib, mkImage }:
let format = pkgs.formats.yaml { };
in {
  default = mkImage {
    options = { config, ... }:
      with lib; {
        package = mkOption {
          default =
            pkgs.home-assistant.overrideAttrs (_: { doInstallCheck = false; });
          type = types.package;
          description = ''
            Home assistant package
          '';
        };

        uid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            UID for home assistant
          '';
        };
        gid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            GID for home assistant
          '';
        };

        port = mkOption {
          type = types.port;
          default = 5000;
          description = ''
            Port for web interface.
          '';
        };
        bind = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            The address to which the service should bind.
          '';
        };

        config = mkOption {
          type = types.nullOr (types.submodule { freeformType = format.type; });

          default = null;
        };

        extraPackages = mkOption {
          type = types.functionTo (types.listOf types.package);
          default = _: [ ];
          description = ''
            List of packages to add to propagatedBuildInputs.
          '';
        };

        customLovelaceModules = mkOption {
          type = types.listOf types.package;
          default = [ ];

          description = ''
            List of custom lovelace card packages to load as lovelace resources.
          '';
        };

        defaultComponents = mkOption {
          type = with types; listOf (enum config.package.availableComponents);
          default = [ ];
          description =
            "List of components shipped with package which should be enabled.";
        };

        customComponents = mkOption {
          type = types.listOf (types.addCheck types.package
            (p: p.isHomeAssistantComponent or false) // {
              name = "home-assistant-component";
              description = "package that is a Home Assistant component";
            });
          default = [ ];
          description = ''
            List of custom component packages to install.
          '';
        };
      };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";
        configDir = "/var/lib/hass";

        #https://github.com/NixOS/nixpkgs/blob/105b791fa9c300b8fd992ba15269932c9a8532a2/nixos/modules/services/home-automation/home-assistant.nix#L55C1-L68C10
        # Post-process YAML output to add support for YAML functions, like
        # secrets or includes, by naively unquoting strings with leading bangs
        # and at least one space-separated parameter.
        # https://www.home-assistant.io/docs/configuration/secrets/
        renderYAMLFile = fn: yaml:
          pkgs.runCommand fn { preferLocalBuilds = true; } ''
            cp ${format.generate fn yaml} $out
            sed -i -e "s/'\!\([a-z_]\+\) \(.*\)'/\!\1 \2/;s/^\!\!/\!/;" $out
          '';

        defaultConfig = {
          http = {
            server_host = config.bind;
            server_port = config.port;
          };
        };

        configData = lib.attrsets.recursiveUpdate defaultConfig
          (lib.optionalAttrs (config.config != null) config.config);
        configFile = renderYAMLFile "configuration.yaml" configData;

        requiredDefaultComponents = [
          "default_config"
          "met"
          "application_credentials"
          "frontend"
          "hardware"
          "logger"
          "network"
          "system_health"

          # key features
          "automation"
          "person"
          "scene"
          "script"
          "tag"
          "zone"

          # built-in helpers
          "counter"
          "input_boolean"
          "input_button"
          "input_datetime"
          "input_number"
          "input_select"
          "input_text"
          "schedule"
          "timer"

          # non-supervisor
          "backup"
        ];

        availableComponents = config.package.availableComponents;
        defaultComponents = requiredDefaultComponents
          ++ config.package.extraComponents ++ config.defaultComponents;

        components =
          builtins.filter (comp: builtins.elem comp defaultComponents)
          availableComponents;

        package = (config.package.override (old: {
          extraComponents = components;
          extraPackages = ps:
            (old.extraPackages or (_: [ ]) ps)
            ++ (lib.concatMap (comp: comp.propagatedBuildInputs or [ ])
              config.customComponents) ++ (config.extraPackages ps);
        }));

        customLovelaceModulesDir = pkgs.buildEnv {
          name = "home-assistant-custom-lovelace-modules";
          paths = config.customLovelaceModules;
        };

        initScript = pkgs.writeShellApplication {
          name = "home-assistant-entrypoint";
          runtimeInputs = [ pkgs.coreutils package ];
          text = ''
            # Let's start

            mkdir -p "${configDir}"
            #configuration
            rm -f "${configDir}/configuration.yaml"
            ln -s ${configFile} "${configDir}/configuration.yaml"

            #customLovelaceModules
            mkdir -p "${configDir}/www"
            ln -fns ${customLovelaceModulesDir} "${configDir}/www/nixos-lovelace-modules"

            #customComponents
            ${lib.strings.concatStringsSep "\n" (lib.lists.flatten (map
              (component: [
                ""
                "#component ${component.name}"
                ''
                  find "${component}" -name manifest.json -exec sh -c 'ln -fns "$(dirname $1)" "${configDir}/custom_components/" ''
                "' sh {} ';'"
              ]) config.customComponents))}

            #Running preStart hook
            ${config.preStart}

            hass --config ${configDir}
          '';
        };

        hashParts = [ (toString config.bind) (toString config.port) ]
          ++ components ++ ((config.package.extraPackages or (_: [ ]))
            config.package.python.pkgs) ++ [ configFile.outPath ]
          ++ config.customLovelaceModules;
        configHash =
          builtins.hashString "md5" (lib.strings.concatStrings hashParts);
      in {
        name = "home-assistant";
        tag = "${config.package.version}-${configHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${configDir}"
          chown -R ${UIDGID} "${configDir}"
        '';

        config = {
          Env = [ "PYTHONPATH=${package.pythonPath}" ];

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = UIDGID;
        };
      };
  };
}
