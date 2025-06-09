{
  description = "Custom OCI images with internal based configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs = { nixpkgs-lib.follows = "nixpkgs"; };
    };
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };

    nix-snapshotter = {
      url = "github:pdtpartners/nix-snapshotter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    search = {
      url = "github:NuschtOS/search";
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.git-hooks-nix.flakeModule

        ./flake-modules
      ];

      systems = [ "x86_64-linux" ];

      perSystem = { config, inputs', pkgs, lib, system, ... }:
        let
          internal = import ./internal {
            inherit lib;
            inherit pkgs;
          };
          inherit (internal) mkImage;

          ignoredAttributes =
            [ "extend" "override" "overrideScope" "overrideDerivation" ];

          repoUrl = "https://github.com/XertDev/nix-custom-images";

          callPackage = pkgs.lib.callPackageWith (pkgs // {
            inherit callPackage;
            inherit mkImage;
          });

          imageDefinitions =
            builtins.mapAttrs (_: v: builtins.removeAttrs v ignoredAttributes)
            (builtins.removeAttrs (callPackage ./images { }) ignoredAttributes);

          images = builtins.mapAttrs
            (_: val: builtins.mapAttrs (_: val: val.builder) val)
            imageDefinitions;

          imageOptions = builtins.mapAttrs
            (_: val: builtins.mapAttrs (_: val: val.optionsModule) val)
            imageDefinitions;

          scopes = lib.lists.flatten (map (val:
            lib.attrsets.mapAttrsToList (k: v: {
              name = "${val}-${k}";
              optionsPrefix = "${val}.${k}";
              modules = [ v ];
              urlPrefix = "${repoUrl}/tree/master";
            }) imageOptions."${val}") (builtins.attrNames imageOptions));
        in {
          pre-commit.settings.hooks = {
            deadnix.enable = true;
            nixfmt-classic.enable = true;
          };
          devShells.default = pkgs.mkShell {
            shellHook = ''
              ${config.pre-commit.installationScript}
            '';
          };

          inherit images;
          packages = {
            docs = inputs'.search.packages.mkMultiSearch {
              title = "Custom images";
              inherit scopes;
            };
            githubDocs = inputs'.search.packages.mkMultiSearch {
              title = "Custom images";
              baseHref = "/nix-custom-images/";
              inherit scopes;
            };
          };

          apps = let
            imageNames = builtins.attrNames images;

            attrsetToString = val:
              if builtins.isString val then
                lib.strings.escapeNixString val
              else if builtins.isInt val || builtins.isFloat val then
                builtins.toString val
              else if builtins.isBool val then
                lib.boolToString val
              else if builtins.isList val then
                "[${
                  lib.strings.concatMapStringsSep " " (x: attrsetToString x) val
                }]"
              else if builtins.isAttrs val then
                "{${
                  lib.strings.concatStringsSep " " (lib.attrsets.mapAttrsToList
                    (key: value: ''"${key}" = ${attrsetToString value};'') val)
                }}"
              else
                "null";
          in {
            docker-size-summary = {
              type = "app";
              program = (pkgs.writeShellScript "" (let
                name = "temporary";
                tag = "analysis";

                subtypeTasks = lib.lists.flatten (map (val:
                  (lib.attrsets.mapAttrsToList (k: _: {
                    name = "${val}-${k}";
                    command = let
                      args = imageDefinitions."${val}"."${k}".defaultBuildArgs
                        // {
                          inherit tag;
                          inherit name;
                        };
                    in ''
                      nix build --print-out-paths --no-link --impure --expr 'with builtins.getFlake (builtins.toString ./.); images.${system}.${val}.${k} ${
                        attrsetToString args
                      }' 2>/dev/null
                    '';
                  }) images.${val})) imageNames);
              in ''
                declare -i FAILED=0

                ${lib.strings.concatStringsSep "\n" (map (val: ''
                  # Build image
                  IMAGE_STREAM=$(${val.command})

                  # Load image to registry
                  $IMAGE_STREAM 2>/dev/null | docker image load -q > /dev/null

                  # Fetch size
                  SIZE=$(docker inspect -f "{{ .Size }}" ${name}:${tag} | ${pkgs.coreutils}/bin/numfmt --to=si)
                  if [[ $? -ne 0 ]]; then
                      ((++FAILED))
                  fi

                  # Cleanup
                  docker image rm ${name}:${tag} > /dev/null
                  nix store delete $IMAGE_STREAM > /dev/null 2>&1

                  echo "${val.name}" - $SIZE
                '') subtypeTasks)}

                if [[ $FAILED -ne 0 ]]; then
                  exit 1
                fi
              '')).outPath;
            };

            test-images = {
              type = "app";
              program = (pkgs.writeShellScript "" (let
                name = "temporary";
                tag = "test";
              in ''
                LOG_DIR=$(mktemp -d)
                trap "rm -f -- $''${LOG_DIR@Q}" EXIT

                declare -i PASSED=0
                declare -i FAILED=0
                declare -i TOTAL=0

                ${lib.strings.concatStringsSep "\n" (lib.lists.flatten (map
                  (val:
                    (lib.attrsets.mapAttrsToList (k: _: ''
                      echo "Tests for ${val}-${k}:"
                      ${lib.strings.concatStringsSep "\n" (map (test:
                        let
                          containerName = "custom-images-test";

                          args = test.config.args // {
                            inherit tag;
                            inherit name;
                          };
                          imageStream = ''
                            nix build --print-out-paths --no-link --impure --expr 'with builtins.getFlake (builtins.toString ./.); images.${system}.${val}.${k} ${
                              attrsetToString args
                            }' 2>/dev/null
                          '';

                          portsParams = lib.strings.concatStringsSep " "
                            (map (x: "-p ${x}") test.config.ports);
                        in ''
                          echo -n "  Test ${test.name}: "

                          # Preparing iamge
                          IMAGE_STREAM=$(${imageStream})
                          $IMAGE_STREAM 2>/dev/null | docker image load -q > /dev/null

                          # Starting image
                          # todo: collecting logs
                          docker run -d ${portsParams} --name=${containerName} ${name}:${tag} > /dev/null

                          # Run test

                          ((++TOTAL))
                          ${test.script} > "$LOG_DIR/run.log" 2>&1

                          if [[ $? -eq 0 ]]; then
                            ((++PASSED))
                            echo "Passed"
                          else
                            ((++FAILED))
                            echo "Failed"

                            echo "  Logs:"
                            cat "$LOG_DIR/run.log" | xargs -0 -i echo "   {}"

                            echo "  Docker logs:"
                            docker logs ${containerName}
                          fi

                          # Cleanup
                          docker container stop ${containerName} > /dev/null
                          docker container rm ${containerName} > /dev/null
                          docker image rm ${name}:${tag} > /dev/null
                          nix store delete $IMAGE_STREAM > /dev/null 2>&1
                        '') imageDefinitions.${val}.${k}.tests)}
                    '') images.${val})) imageNames))}

                echo "==== SUMMARY ===="
                echo "Total: $TOTAL Passed: $PASSED Failed: $FAILED"
              '')).outPath;
            };
          };
        };
    };
}
