# Tracks as a Nix package: the app with its gems and precompiled assets in
# the (read-only) store. What Rails writes at runtime, and the site
# configuration, are symlinks into stateDir, which the NixOS module creates:
#
#   config/site.yml -> <stateDir>/site.yml
#   log/            -> <stateDir>/log
#   tmp/            -> <stateDir>/tmp
#   storage/        -> <stateDir>/storage      (Active Storage)
#   db/assets/      -> <stateDir>/attachments  (Paperclip attachments)
#
# After a change to Gemfile.lock, regenerate gemset.nix:
#   nix run nixpkgs#bundix
{
  lib,
  stdenv,
  bundlerEnv,
  ruby_3_3,
  nodejs,
  makeWrapper,
  version ? "dev",
  src ? lib.cleanSource ../.,
  stateDir ? "/var/lib/tracks",
}:

let
  ruby = ruby_3_3;

  # Without mini_racer (group therubyracer, a prebuilt V8): ExecJS uses Node.
  # Without the optional development, test and stripe groups.
  withoutGroups = [
    "therubyracer"
    "development"
    "test"
    "stripe"
  ];

  # bundix also puts libv8-node, mini_racer's dependency, in the default
  # group, so the groups below don't keep it out (and it downloads Node)
  gemset = removeAttrs (import ../gemset.nix) [
    "mini_racer"
    "libv8-node"
  ];

  gems = bundlerEnv {
    name = "tracks-gems-${version}";
    inherit ruby gemset;
    gemfile = ../Gemfile;
    lockfile = ../Gemfile.lock;
    groups = [
      "default"
      "assets"
      "sqlite"
      "mysql"
      "postgresql"
    ];
  };

  env = {
    RAILS_ENV = "production";
    BUNDLE_WITHOUT = lib.concatStringsSep ":" withoutGroups;
    EXECJS_RUNTIME = "Node";
  };
in
stdenv.mkDerivation {
  pname = "tracks";
  inherit version src;

  nativeBuildInputs = [
    makeWrapper
    nodejs
    gems
    gems.wrappedRuby
  ];

  buildPhase = ''
    runHook preBuild

    cp ${./database.yml} config/database.yml
    cp config/site.yml.tmpl config/site.yml

    ${lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") env)}
    # loading the app for the asset pipeline needs a database configuration,
    # not a database
    export DATABASE_TYPE=sqlite3 DATABASE_NAME=/dev/null
    export SECRET_KEY_BASE=precompile-only
    export HOME=$TMPDIR

    RAILS_GROUPS=assets bundle exec rake assets:precompile

    rm config/site.yml
    rm -rf tmp log/*.log
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -r . $out/share/tracks
    app=$out/share/tracks

    # development and Docker leftovers
    rm -rf $app/.use-docker $app/test $app/test-envs $app/.git

    rm -rf $app/log $app/tmp $app/storage $app/db/assets
    ln -s ${stateDir}/site.yml    $app/config/site.yml
    ln -s ${stateDir}/log         $app/log
    ln -s ${stateDir}/tmp         $app/tmp
    ln -s ${stateDir}/storage     $app/storage
    ln -s ${stateDir}/attachments $app/db/assets

    # tracks-rails server|console|runner ..., tracks-rake db:migrate ...
    # (bin/rails is a shell script for Docker, which the rails executable of
    # the gem doesn't recognise as an app: use bin/run-rails)
    for cmd in rails rake; do
      if [ $cmd = rails ]; then
        run="exec ${gems.wrappedRuby}/bin/ruby $app/bin/run-rails"
      else
        run="exec rake"
      fi
      makeWrapper ${gems}/bin/bundle $out/bin/tracks-$cmd \
        --chdir $app \
        ${
          lib.concatStrings (lib.mapAttrsToList (k: v: "--set-default ${k} ${lib.escapeShellArg v} ") env)
        } \
        --prefix PATH : ${lib.makeBinPath [ nodejs ]} \
        --add-flags "$run"
    done

    runHook postInstall
  '';

  passthru = {
    inherit gems ruby stateDir;
  };

  meta = {
    description = "Tracks, a web-based todo application following Getting Things Done";
    homepage = "https://www.getontracks.org/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "tracks-rails";
  };
}
