# NixOS VM test of the module (nix flake check): Tracks with a local
# MariaDB, the schema loaded on the first start, the first user signed up,
# an action added through the REST API, and a restart that migrates instead
# of loading the schema again.
{ module }:
{
  name = "tracks";

  nodes.machine = { ... }: {
    imports = [ module ];
    virtualisation.memorySize = 2048;
    virtualisation.cores = 4;
    services.tracks = {
      enable = true;
      settings.time_zone = "Brussels";
    };
  };

  testScript = ''
    machine.wait_for_unit("tracks.service")
    machine.wait_for_open_port(3000, timeout=1800)

    # with no users yet, /login sends you to the signup of the first user
    machine.succeed("curl -sSfL http://127.0.0.1:3000/ | grep -i 'tracks'")

    # assets are precompiled and served by Rails
    css = machine.succeed(
      "curl -sSf http://127.0.0.1:3000/login -L | grep -o '/assets/[^\"]*\\.css' | head -1"
    ).strip()
    machine.succeed(f"curl -sSf http://127.0.0.1:3000{css} >/dev/null")

    # create the admin through the console wrapper, then use the API
    machine.succeed(
      "tracks-rails runner \"User.create!(login: 'admin', password: 'secret-pw-123', "
      "password_confirmation: 'secret-pw-123', is_admin: true).create_preference(locale: 'en')\""
    )
    machine.succeed(
      "curl -sSf -u admin:secret-pw-123 -H 'Content-Type: text/xml' "
      "-d '<context><name>home</name></context>' http://127.0.0.1:3000/contexts.xml"
    )
    machine.succeed(
      "curl -sSf -u admin:secret-pw-123 -H 'Content-Type: text/xml' "
      "-d '<todo><description>Test from the VM</description><context_id>1</context_id></todo>' "
      "http://127.0.0.1:3000/todos.xml"
    )
    machine.succeed(
      "curl -sSf -u admin:secret-pw-123 http://127.0.0.1:3000/todos.xml | grep 'Test from the VM'"
    )

    # a restart keeps the data and the secret, and runs migrations
    machine.succeed("test -s /var/lib/tracks/secret_key_base")
    machine.systemctl("restart tracks.service")
    machine.wait_for_open_port(3000, timeout=1800)
    machine.succeed(
      "curl -sSf -u admin:secret-pw-123 http://127.0.0.1:3000/todos.xml | grep 'Test from the VM'"
    )
    machine.succeed("test $(journalctl -u tracks.service | grep -c 'empty database, loading db/schema.rb') = 1")
  '';
}
