{
  description = "frogr — Flickr Remote Organizer, ported to Ruby GTK4/Libadwaita";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let frogr = pkgs.callPackage ./nix/frogr.nix { }; in
        {
          inherit frogr;
          default = frogr;
        });

      devShells = forAllSystems (pkgs:
        let
          env = pkgs.callPackage ./nix/gems.nix { };

          # Everything the ruby-gnome stack introspects at runtime.
          #
          # The `.out` selections are deliberate: mkShell splices split-output
          # packages to their `bin`/`dev` outputs, and the GObject typelibs
          # live in `out`. Without this, GI_TYPELIB_PATH points at glib-bin,
          # which has no typelibs, and `require "gtk4"` fails on Gio.
          runtimeLibs = with pkgs; [
            glib.out
            gtk4.out
            libadwaita.out
            gdk-pixbuf.out
            graphene.out
            pango.out
            cairo.out
            atk.out
            harfbuzz.out
            librsvg.out
          ];
        in
        {
          default = pkgs.mkShell {
            name = "frogr-rb";

            packages = with pkgs; [
              env.wrappedRuby
              bundix
              pkg-config
              gtk4.dev
              libadwaita.dev
              gobject-introspection
              gtk4 # for gtk4-builder-tool / gtk4-demo while developing
              glib # glib-compile-schemas
            ] ++ runtimeLibs;

            shellHook = ''
              # bundix propagates a plain ruby; the wrapped one — the only ruby
              # that can see the bundled gems — has to win the PATH race.
              export PATH="${env.wrappedRuby}/bin:$PATH"
              export GI_TYPELIB_PATH="${pkgs.lib.makeSearchPath "lib/girepository-1.0" runtimeLibs}"
              export XDG_DATA_DIRS="${pkgs.gtk4}/share:${pkgs.libadwaita}/share:${pkgs.shared-mime-info}/share:''${XDG_DATA_DIRS:-}"
              export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
              export FROGR_DATA_DIR="$PWD/data"

              echo "frogr-rb devshell — ruby $(ruby -e 'print RUBY_VERSION'), gtk4 gem $(ruby -e 'require "gtk4"; print Gtk::Version::STRING' 2>/dev/null || echo '(not loadable)')"
              echo "  run the app:  ruby bin/frogr"
              echo "  relock gems:  bundle lock --update && bundix --lockfile=Gemfile.lock --gemset=gemset.nix"
            '';
          };
        });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.frogr}/bin/frogr";
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
