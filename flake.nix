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

          # Everything the ruby-gnome stack dlopen()s or introspects at runtime.
          runtimeLibs = with pkgs; [
            glib
            gtk4
            libadwaita
            gdk-pixbuf
            graphene
            pango
            cairo
            atk
            harfbuzz
            librsvg
          ];
        in
        {
          default = pkgs.mkShell {
            name = "frogr-rb";

            packages = with pkgs; [
              env.wrappedRuby
              bundler
              bundix
              pkg-config
              gtk4.dev
              libadwaita.dev
              gobject-introspection
              gtk4 # for gtk4-builder-tool / gtk4-demo while developing
              glib # glib-compile-schemas
            ] ++ runtimeLibs;

            shellHook = ''
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
