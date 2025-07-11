{ pkgs, lib, mkImage, ... }:
let
  locationOptions = with lib; {
    proxyPass = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Sets proxy_pass directive.
      '';
    };
    proxyWebsockets = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Support websocket proxying.
      '';
    };

    tryFiles = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Sets try_files directive.
      '';
    };

    root = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Root directory
      '';
    };

    return = mkOption {
      type = types.nullOr (types.oneOf [ types.str types.int ]);
      default = null;
      description = ''
        Sets return directive.
      '';
    };

    defaultProxySettings = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Add default proxy settings.
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Lines appended at the end of location section.
      '';
    };
  };

  virtualHostOptions = with lib; {
    listenPorts = mkOption {
      type = types.listOf (types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = ''
              Port to listen on.
            '';
          };
          ssl = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Use SSL for this port.
            '';
          };
        };
      });
      default = [ ];
      # todo: add assertions
      description = ''
        List of ports which this vhost binds to.

        Selecting this option will disable the default listen ports for HTTP and SSL.
        This option is incompatible with 'addSSL' and 'onlySSL'.

        If you want to activate 'ssl' to true, you will need to set 'sslCertificate' and 'sslCertificateKey'.
      '';
    };

    serverAliases = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Names for served virtual hosts.
      '';
    };

    addSSL = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable HTTPS.
      '';
    };
    onlySSL = mkOption {
      type = types.bool;
      default = false;
      description = ''
        HTTPS only mode. Listen only on port 443.
      '';
    };

    sslCertificate = mkOption {
      type = types.path;
      description = ''
        SSL certificate path.
      '';
    };
    sslCertificateKey = mkOption {
      type = types.path;
      description = ''
        SSL certificate key path.
      '';
    };

    locations = mkOption {
      type = types.attrsOf (types.submodule { options = locationOptions; });
      default = { };
      description = ''
        Locations definition.
      '';
    };
  };

  options = with lib; {
    package = mkPackageOption pkgs "nginx" { };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = ''
        UID for nginx.
      '';
    };
    gid = mkOption {
      type = types.int;
      default = 1000;
      description = ''
        GID for nginx.
      '';
    };

    clientMaxBodySize = mkOption {
      type = types.str;
      default = "10m";
      description = ''
        Sets client_max_body_size directive.
      '';
    };

    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule { options = virtualHostOptions; });
      default = { localhost = { }; };
      description = ''
        Virtual hosts definition.
        Entry key would be used as serverName for vhost.
      '';
    };
  };
in {
  default = mkImage {
    inherit options;

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        defaultProxyConfig = pkgs.writeText "default-proxy-config.conf" ''
          proxy_set_header Host $host;
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Uri $request_uri;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Real-IP $remote_addr;

          proxy_redirect http:// $scheme://;
        '';

        vhostConfig = lib.strings.concatStringsSep "\n"
          (lib.attrsets.mapAttrsToList (name: vhost:
            let
              defaultSSLPort = 443;
              defaultHTTPPort = 80;
              listenAddresses = [ "0.0.0.0" "[::0]" ];

              customlistenSSL = lib.lists.any (x: x.ssl) vhost.listenPorts;
              SSLenabled = vhost.addSSL || vhost.onlySSL || customlistenSSL;

              locations = lib.strings.concatStringsSep "\n"
                (lib.attrsets.mapAttrsToList (path: location: ''
                  location ${path} {
                    ${
                      lib.strings.optionalString (location.proxyPass != null)
                      "proxy_pass ${location.proxyPass};"
                    }
                    ${
                      lib.strings.optionalString location.proxyWebsockets ''
                        proxy_http_version 1.1;
                        proxy_set_header Upgrade $http_upgrade;
                        proxy_set_header Connection $connection_upgrade;
                      ''
                    }

                    ${
                      lib.strings.optionalString (location.tryFiles != null)
                      "try_files ${location.tryFiles};"
                    }
                    ${
                      lib.strings.optionalString (location.root != null)
                      "root ${location.root};"
                    }
                    ${
                      lib.strings.optionalString (location.return != null)
                      "return ${toString location.return};"
                    }

                    ${
                      lib.strings.optionalString (location.proxyPass != null
                        && location.defaultProxySettings)
                      "include ${defaultProxyConfig};"
                    }

                    ${location.extraConfig}
                  }
                '') vhost.locations);

              defaultListenPorts = lib.optionals (!vhost.onlySSL) [{
                port = defaultHTTPPort;
                ssl = false;
              }] ++ lib.optionals SSLenabled [{
                port = defaultSSLPort;
                ssl = true;
              }];

              listenPorts = if vhost.listenPorts != [ ] then
                vhost.listenPorts
              else
                defaultListenPorts;

              listen = lib.lists.flatten (map (addr:
                map (portDecl: portDecl // { inherit addr; }) listenPorts)
                listenAddresses);

              mkListenLine = { addr, port, ssl }:
                "listen ${addr}:${builtins.toString port}"
                + lib.strings.optionalString ssl " ssl" + ";";
              listenConfig =
                lib.strings.concatMapStringsSep "\n" mkListenLine listen;
            in ''
              server {
                ${listenConfig}

                server_name ${name} ${
                  lib.strings.concatStringsSep " " vhost.serverAliases
                };
                ${lib.strings.optionalString SSLenabled "	http2 on;"}
                ${
                  lib.strings.optionalString SSLenabled ''
                    ssl_certificate ${vhost.sslCertificate};
                    ssl_certificate_key ${vhost.sslCertificateKey};
                  ''
                }

                ${locations}
              }
            '') config.virtualHosts);

        configText = ''
          pid /run/nginx/nginx.pid;
          error_log stderr;

          daemon off;

          events {}

          http {
            # Load mime types and configure maximum size of the types hash tables.
            include ${pkgs.mailcap}/etc/nginx/mime.types;
            types_hash_max_size 2688;

            include ${config.package}/conf/fastcgi.conf;
            include ${config.package}/conf/uwsgi_params;
            default_type application/octet-stream;

            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;

            # Map $connection_upgrade is used for websocket proxying
            map $http_upgrade $connection_upgrade {
              default upgrade;
              \'\'      close;
            }

            client_max_body_size ${config.clientMaxBodySize};

            server_tokens off;

            ${vhostConfig}
          }
        '';

        configFile = pkgs.writers.writeNginxConfig "nginx.conf" configText;

        initScript = pkgs.writeShellApplication {
          name = "nginx-entrypoint";
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            #Running preStart hook
            ${config.preStart}

            # Run server
            ${config.package}/bin/nginx -c '${configFile}'
          '';
        };

        configHash = builtins.hashString "md5" configText;
      in {
        name = "nginx";
        tag = "${config.package.version}-${configHash}";

        contents = with pkgs;
          [
            (dockerTools.fakeNss.override {
              extraPasswdLines = [
                "nginx:x:${UIDGID}:nginx web server user:/var/empty:/bin/sh"
              ];
              extraGroupLines =
                [ "nginx:x:${toString config.gid}:nginx" "nogroup:x:65534:" ];
            })
          ];

        enableFakechroot = true;
        fakeRootCommands = ''
          # Create required directories
          mkdir -p tmp/nginx_client_body
          mkdir -p tmp/nginx_fastcgi
          mkdir -p tmp/nginx_uwsgi
          mkdir -p tmp/nginx_scgi
          mkdir -p tmp/nginx_proxy

          mkdir -p var/log/nginx
          mkdir -p var/cache/nginx/client_body

          mkdir -p run/nginx/

          # Chown
          chown -R ${UIDGID} ./run/nginx
          chown -R ${UIDGID} ./tmp/nginx_client_body
          chown -R ${UIDGID} ./tmp/nginx_fastcgi
          chown -R ${UIDGID} ./tmp/nginx_uwsgi
          chown -R ${UIDGID} ./tmp/nginx_scgi
          chown -R ${UIDGID} ./tmp/nginx_proxy
          chown -R ${UIDGID} ./var/log/nginx
          chown -R ${UIDGID} ./var/cache/nginx
        '';

        config = {
          User = UIDGID;
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };
  };
}
