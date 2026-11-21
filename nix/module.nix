# NixOS module for Tracks: services.tracks.
#
#   services.tracks = {
#     enable = true;
#     settings.time_zone = "Europe/Brussels";
#     settings.admin_email = "me@example.org";
#   };
#
# By default it creates a local MariaDB database reached over its socket and
# serves on 127.0.0.1:3000; put a reverse proxy (with TLS) in front of it.
# `tracks-rails` (run as root) runs Rails commands as the tracks user, e.g.
# `tracks-rails console`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tracks;
  db = cfg.database;
  stateDir = cfg.package.passthru.stateDir;

  yaml = pkgs.formats.yaml { };
  siteYml = yaml.generate "tracks-site.yml" cfg.settings;

  mysqlLocal = db.createLocally && db.type == "mysql2";
  pgLocal = db.createLocally && db.type == "postgresql";

  environment = {
    RAILS_ENV = "production";
    RAILS_SERVE_STATIC_FILES = "1";
    RAILS_LOG_TO_STDOUT = "1";
    DATABASE_TYPE = db.type;
    DATABASE_NAME = db.name;
    DATABASE_ENCODING = db.encoding;
  }
  // lib.optionalAttrs (db.type != "sqlite3") {
    DATABASE_USERNAME = db.user;
  }
  // lib.optionalAttrs (db.host != null) { DATABASE_HOST = db.host; }
  // lib.optionalAttrs (db.port != null) { DATABASE_PORT = toString db.port; }
  // lib.optionalAttrs (db.socket != null) { DATABASE_SOCKET = db.socket; }
  // cfg.extraEnvironment;

  # the secrets, read from files at start so they stay out of the store
  loadSecrets = ''
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -e "$CREDENTIALS_DIRECTORY/secret_key_base" ]; then
      SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"
    else
      SECRET_KEY_BASE="$(< ${stateDir}/secret_key_base)"
    fi
    export SECRET_KEY_BASE
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -e "$CREDENTIALS_DIRECTORY/db_password" ]; then
      DATABASE_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/db_password")"
      export DATABASE_PASSWORD
    fi
  '';

  # tracks-rails for the administrator: the service's environment, as the
  # tracks user
  adminWrapper = pkgs.writeShellScriptBin "tracks-rails" ''
    set -euo pipefail
    if [ "$(id -u)" != 0 ]; then
      echo "tracks-rails: run as root (it switches to the ${cfg.user} user)" >&2
      exit 1
    fi
    args=()
    for a in "$@"; do args+=("$(printf '%q' "$a")"); done
    exec ${pkgs.util-linux}/bin/runuser -u ${cfg.user} -- ${pkgs.bash}/bin/bash -c '
      set -euo pipefail
      ${lib.concatStrings (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") environment
      )}
      ${lib.optionalString (cfg.environmentFile != null) "set -a; . ${cfg.environmentFile}; set +a"}
      SECRET_KEY_BASE="$(< ${stateDir}/secret_key_base)"; export SECRET_KEY_BASE
      ${lib.optionalString (
        db.passwordFile != null
      ) ''DATABASE_PASSWORD="$(< ${db.passwordFile})"; export DATABASE_PASSWORD''}
      exec ${cfg.package}/bin/tracks-rails '"''${args[*]}"'
    '
  '';
in
{
  options.services.tracks = {
    enable = lib.mkEnableOption "Tracks, a todo application following Getting Things Done";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The Tracks package (the flake's packages.<system>.tracks).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "tracks";
      description = "User the service runs as; also the database user of a local database.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "tracks";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Puma listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port in the firewall (rather use a reverse proxy).";
    };

    settings = lib.mkOption {
      description = ''
        The contents of config/site.yml; see config/site.yml.tmpl for the keys.
        secret_token is not needed: the secret key base is
        secretKeyBaseFile, or generated in ${"$"}{stateDir}/secret_key_base.
      '';
      type = lib.types.submodule {
        freeformType = yaml.type;
        options = {
          authentication_schemes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "database" ];
          };
          time_zone = lib.mkOption {
            type = lib.types.str;
            default = if config.time.timeZone != null then config.time.timeZone else "UTC";
            defaultText = lib.literalExpression ''config.time.timeZone or "UTC"'';
            description = "Rails time zone name, e.g. Europe/Brussels or Brussels.";
          };
          secure_cookies = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Only send cookies over HTTPS; turn on behind a TLS proxy.";
          };
          force_ssl = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          open_signups = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Let anyone create an account (the first user can always sign up).";
          };
          admin_email = lib.mkOption {
            type = lib.types.str;
            default = "root@localhost";
          };
        };
      };
      default = { };
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File with the Rails secret key base. When null, one is generated on the
        first start in ${"$"}{stateDir}/secret_key_base.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Extra environment variables (KEY=value lines), e.g. secrets of your own.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the service.";
    };

    database = {
      type = lib.mkOption {
        type = lib.types.enum [
          "mysql2"
          "postgresql"
          "sqlite3"
        ];
        default = "mysql2";
        description = "Database adapter (the Docker setup uses mysql2).";
      };
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the database on this machine (MariaDB or PostgreSQL), with a
          database and a socket-authenticated user for Tracks.
        '';
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = if db.type == "sqlite3" then "${stateDir}/tracks.sqlite3" else "tracks";
        defaultText = lib.literalExpression ''"tracks", or "''${stateDir}/tracks.sqlite3" for sqlite3'';
        description = "Database name (for sqlite3, the file).";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = cfg.user;
        defaultText = lib.literalExpression "config.services.tracks.user";
      };
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if pgLocal then "/run/postgresql" else null;
        defaultText = lib.literalExpression ''"/run/postgresql" for a local PostgreSQL, else null'';
        description = "Database host; for PostgreSQL a directory means its socket.";
      };
      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
      };
      socket = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if mysqlLocal then "/run/mysqld/mysqld.sock" else null;
        defaultText = lib.literalExpression ''"/run/mysqld/mysqld.sock" for a local MariaDB, else null'';
        description = "MySQL/MariaDB socket.";
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File with the database password (not needed for a local database).";
      };
      encoding = lib.mkOption {
        type = lib.types.str;
        default = if db.type == "mysql2" then "utf8mb4" else "utf8";
        defaultText = lib.literalExpression ''"utf8mb4" for mysql2, else "utf8"'';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(pgLocal && db.name != db.user);
        message = "services.tracks: a local PostgreSQL database must be named after its user (database.name = database.user).";
      }
      {
        assertion = !(db.createLocally && db.user != cfg.user && db.type != "sqlite3");
        message = "services.tracks: a local database authenticates over its socket, so database.user must be services.tracks.user.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = stateDir;
    };
    users.groups.${cfg.group} = { };

    services.mysql = lib.mkIf mysqlLocal {
      enable = true;
      package = lib.mkDefault pkgs.mariadb;
      ensureDatabases = [ db.name ];
      ensureUsers = [
        {
          name = db.user;
          ensurePermissions = {
            "${db.name}.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    services.postgresql = lib.mkIf pgLocal {
      enable = true;
      ensureDatabases = [ db.name ];
      ensureUsers = [
        {
          name = db.user;
          ensureDBOwnership = true;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    environment.systemPackages = [ adminWrapper ];

    systemd.services.tracks = {
      description = "Tracks";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
      ]
      ++ lib.optional mysqlLocal "mysql.service"
      ++ lib.optional pgLocal "postgresql.service";
      requires = lib.optional mysqlLocal "mysql.service" ++ lib.optional pgLocal "postgresql.service";

      inherit environment;

      script = ''
        set -euo pipefail

        mkdir -p ${stateDir}/{log,tmp,storage,attachments}
        ln -sfn ${siteYml} ${stateDir}/site.yml
        ${lib.optionalString (cfg.secretKeyBaseFile == null) ''
          if [ ! -s ${stateDir}/secret_key_base ]; then
            (umask 077; ${pkgs.openssl}/bin/openssl rand -hex 64 > ${stateDir}/secret_key_base)
          fi
        ''}
        ${loadSecrets}

        # a new database gets the schema, an existing one its migrations
        if ${cfg.package}/bin/tracks-rails runner \
             'exit(ActiveRecord::Base.connection.table_exists?("schema_migrations") ? 0 : 3)'; then
          ${cfg.package}/bin/tracks-rake db:migrate
        else
          status=$?
          if [ "$status" != 3 ]; then exit "$status"; fi
          echo "tracks: empty database, loading db/schema.rb"
          ${cfg.package}/bin/tracks-rake db:schema:load
        fi

        exec ${cfg.package}/bin/tracks-rails server \
          --binding ${lib.escapeShellArg cfg.listenAddress} --port ${toString cfg.port} \
          --pid ${stateDir}/tmp/puma.pid
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "tracks";
        StateDirectoryMode = "0750";
        WorkingDirectory = "${cfg.package}/share/tracks";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        LoadCredential =
          lib.optional (cfg.secretKeyBaseFile != null) "secret_key_base:${cfg.secretKeyBaseFile}"
          ++ lib.optional (db.passwordFile != null) "db_password:${db.passwordFile}";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 300;

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        UMask = "0027";
      };
    };
  };
}
