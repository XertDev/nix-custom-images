{ pkgs, lib, mkImage, gnused, ... }:
let
	format = pkgs.formats.yaml {};
in
{
	default = mkImage {
		options = with lib; {
			package = mkPackageOption pkgs "homepage-dashboard" {};

			uid = mkOption {
				default = 1000;
				type = types.int;
				description = "UID for fava";
			};
			gid = mkOption {
				default = 1000;
				type = types.int;
				description = "GID for fava";
			};

			port = mkOption {
				type = types.port;
				default = 5000;
				description = ''
					Port for web interface
				'';
			};

			bookmarks = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/configs/bookmarks/>.
				'';
				default = [];
			};

			services = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/configs/services/>.
				'';
				default = [];
			};

			widgets = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/widgets/>.
				'';
				default = [];
			};

			kubernetes = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/configs/kubernetes/>.
				'';
				default = {};
			};

			docker = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/configs/kubernetes/>.
				'';
				default = {};
			};

			settings = mkOption {
				type  = format.type;
				description = ''
					See <https://gethomepage.dev/configs/settings/>.
				'';
				default = {};
			};
		};

		image = { config, ... }: let

			UIDGID = "${toString config.uid}:${toString config.gid}";

			configFiles = [
				(format.generate "bookmarks.yaml" config.bookmarks)
				(format.generate "services.yaml" config.services)
				(format.generate "widgets.yaml" config.widgets)
				(format.generate "kubernetes.yaml" config.kubernetes)
				(format.generate "docker.yaml" config.docker)
				(format.generate "settings.yaml" config.settings)
				(pkgs.writeTextFile { name = "custom.css"; text = ""; })
				(pkgs.writeTextFile { name = "custom.js"; text = ""; })
			];

			configDir = pkgs.runCommand "homepage-dashboard-config" {
				paths = configFiles;
				passAsFile = ["paths"];
				preferLocalBuild = true;
				allowSubstitutes = false;
			} ''
				mkdir -p $out
				for i in $(cat $pathsPath); do
					BASENAME=$(basename $i | ${gnused}/bin/sed -n -e 's/^.*-//p')
					ln -s "$i" "$out/"$BASENAME
				done
			'';

			configEnv = "${toString config.port}${configDir}";
			fullConfigHash = builtins.hashString "md5" configEnv;

			cacheDir = "/var/cache/homepage-dashboard";
		in
		{
			name = "homepage-dashboard";
			tag = "${config.package.version}-${fullConfigHash}";

			enableFakechroot = true;
			fakeRootCommands = ''
					mkdir -p "${cacheDir}"
					chown -R "${UIDGID}" "${cacheDir}"
			'';

			contents = with pkgs; [
				fakeNss
			];

			config = {
				Env = [
					"HOMEPAGE_CONFIG_DIR=${configDir}"
					"PORT=${toString config.port}"
					"LOG_TARGETS=stdout"
					"NIXPKGS_HOMEPAGE_CACHE_DIR=${cacheDir}"

					"SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
				];
				Entrypoint = [ (pkgs.lib.meta.getExe config.package) ];
				User = UIDGID;
			};
		};
	};
}