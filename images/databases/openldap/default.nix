{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    options = with lib;
      let
        # Based on https://github.com/NixOS/nixpkgs/blob/4fbaec7faa5c19d7c933bf6afcb550f06303c947/nixos/modules/services/databases/openldap.nix#L33
        ldapValueType = let
          singleLdapValueType = mkOptionType {
            name = "LDAPValueType";
            description = ''
              string ot attrset with 'path' or 'base64' field
            '';
            check = x: isString x || (isAttrs x && (x ? path || x ? base64));
            merge = mergeEqualOption;
          };
        in types.either singleLdapValueType (types.listOf singleLdapValueType);

        ldapAttrsOptions = let
          options = {
            attrs = mkOption {
              type = types.attrsOf ldapValueType;
              default = { };
              description = ''
                Entry attributes;
              '';
            };

            children = mkOption {
              type = let
                hiddenOptions =
                  lib.mapAttrs (_: attr: attr // { visible = false; }) options;
              in types.attrsOf (types.submodule { options = hiddenOptions; });
              default = { };
              description = ''
                Child entries.
              '';
            };

            includes = mkOption {
              type = types.listOf types.path;
              default = [ ];
              description = ''
                Files included for entry.
              '';
            };
          };
        in options;
      in {
        package = mkPackageOption pkgs "openldap" { };

        uid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            UID for openldap.
          '';
        };
        gid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            GID for openldap.
          '';
        };

        settings = mkOption {
          type = types.submodule { options = ldapAttrsOptions; };
          description = ''
            OpenLDAP configuration.
          '';
        };
      };

    image = { config, ... }:
      let
        configDir = "/etc/openldap/slapd.d";
        UIDGID = "${toString config.uid}:${toString config.gid}";

        valueToLdif = value:
          if lib.isAttrs value then
            if value ? "path" then
              "< file://${value.path}"
            else
              ": ${value.base64}"
          else
            " ${lib.replaceStrings [ "\n" ] [ "\n " ] value}";

        attrsToLdif = dn:
          { attrs, children, includes, ... }: ''
            dn: ${dn}

            ${lib.concatStringSep "\n" (lib.flatten (lib.mapAttrsToList
              (attr: values:
                let
                  valuesList =
                    if lib.isList values then values else lib.singleton values;
                in map (value: "${attr}: ${valueToLdif value}") valuesList)
              attrs))}

            ${lib.concatStringsSep "\n" (map (path: ''
              include: file://${path}
            '') includes)}

            ${lib.concatStringsSep "\n"
            (lib.mapAttrsToList (key: value: attrsToLdif "${key},${dn}" value)
              config.children)}
          '';

        configText = attrsToLdif "cn=config" config.settings;
        configHash = builtins.hashString "md5" configText;

        configFile = pkgs.writeText "config.ldif" configText;

        initScript = pkgs.wrtieShellApplication {
          name = "openldap-entrypoint";
          text = ''
            #Test configuration
            ${config.package}/bin/slaptest -u -F "${configDir}"

            #Load config
            if [! -e "${configDir}/cn=config.ldif" ]; then
              ${config.package}/bin/slapadd -F ${configDir} -bcn=config -l ${configFile}
            fi

            #Start server
            ${config.package}/libexec/slapd -d 0 -F "${configDir} -h ldap:///
          '';
        };
      in {
        name = "openldap";
        tag = "${config.package.version}-${configHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${configDir}
          chown -R "${UIDGID}" "${configDir}"
        '';

        config = {
          User = UIDGID;
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };
  };
}
