{
  description = "Tracks, a web-based todo application following Getting Things Done";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      version = "2.7.1-${self.shortRev or self.dirtyShortRev or "dirty"}";
    in
    {
      packages = forAllSystems (pkgs: rec {
        tracks = pkgs.callPackage ./nix/package.nix {
          inherit version;
          src = self;
        };
        default = tracks;
      });

      overlays.default = final: prev: {
        tracks = final.callPackage ./nix/package.nix {
          inherit version;
          src = self;
        };
      };

      nixosModules.default = { pkgs, ... }: {
        imports = [ ./nix/module.nix ];
        services.tracks.package =
          nixpkgs.lib.mkDefault
            self.packages.${pkgs.stdenv.hostPlatform.system}.tracks;
      };

      # nix flake check: boots a VM with the module and a local MySQL
      checks = forAllSystems (pkgs: {
        vm = pkgs.testers.runNixOSTest (import ./nix/test.nix { module = self.nixosModules.default; });
      });

      # Development: ruby, bundler and the libraries of the native gems; gems
      # go to vendor/bundle with `bundle install`.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            ruby_3_3
            nodejs
            bundix
            pkg-config
            libyaml
            sqlite
            libmysqlclient
            postgresql
            zlib
            openssl
            libxml2
            libxslt
          ];
          shellHook = ''
            export BUNDLE_PATH=vendor/bundle
            export BUNDLE_WITHOUT=therubyracer:stripe
            export BUNDLE_WITH=development:test
            export EXECJS_RUNTIME=Node
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
