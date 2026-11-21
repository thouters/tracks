# Tracks with Nix

The flake in the repository root provides:

| Output | What |
| --- | --- |
| `packages.<system>.tracks` | Tracks with its gems and precompiled assets (`nix build`) |
| `nixosModules.default` | `services.tracks`, see `module.nix` for the options |
| `overlays.default` | adds `pkgs.tracks` |
| `checks.<system>.vm` | NixOS VM test of the module (`nix flake check`) |
| `devShells.<system>.default` | Ruby 3.3, Node, bundix and the libraries of the native gems |

## Deploying on NixOS

```nix
# flake.nix of the machine
inputs.tracks.url = "github:thouters/tracks/nix-flake";

# configuration
imports = [ inputs.tracks.nixosModules.default ];
services.tracks = {
  enable = true;
  settings = {
    time_zone = "Brussels";
    admin_email = "me@example.org";
    secure_cookies = true;      # behind a TLS proxy
  };
};
```

This runs Puma on 127.0.0.1:3000 with a local MariaDB (database `tracks`,
user `tracks`, over the socket). Put a reverse proxy with TLS in front of it.
`database.type` can also be `postgresql` (local or not) or `sqlite3`.

State lives in `/var/lib/tracks`: `site.yml` (generated from `settings`),
`secret_key_base` (generated on the first start unless `secretKeyBaseFile` is
set), `log/`, `tmp/`, `storage/` and `attachments/`.

On every start the service loads `db/schema.rb` into an empty database, or
runs the migrations on an existing one.

As root, `tracks-rails` runs Rails commands as the `tracks` user with the
service's environment, e.g. `tracks-rails console`.

## Moving the Docker installation over

1. Dump the MySQL database of the Docker setup:
   `docker compose exec db mysqldump tracks > tracks.sql`
2. Enable the module, let it start once (it creates the database), stop it:
   `systemctl stop tracks`
3. Import the dump: `mysql tracks < tracks.sql`
4. Copy `db/assets/production` of the Docker volume to
   `/var/lib/tracks/attachments/production`, owned by `tracks`.
5. To keep existing sessions, put the old `secret_token` of `site.yml` in a
   file and point `services.tracks.secretKeyBaseFile` at it.
6. `systemctl start tracks`: it runs any pending migrations.

## After changing Gemfile.lock

Regenerate `gemset.nix` (in the dev shell, or `nix run nixpkgs#bundix`):

```sh
bundix
```

`nix/package.nix` leaves out `mini_racer` and `libv8-node` (ExecJS uses
Node) and the optional development, test and stripe groups.

## Development

```sh
nix develop
bundle install      # into vendor/bundle
```
