{ lib
, stdenv
, callPackage
, makeWrapper
, wrapGAppsHook4
, gobject-introspection
, glib
, gtk4
, libadwaita
, gdk-pixbuf
, graphene
, pango
, cairo
, atk
, librsvg
, shared-mime-info
, gsettings-desktop-schemas
, desktop-file-utils
}:

let
  env = callPackage ./gems.nix { };

  runtimeLibs = [ glib gtk4 libadwaita gdk-pixbuf graphene pango cairo atk librsvg ];
in
stdenv.mkDerivation {
  pname = "frogr";
  version = "1.7";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [ makeWrapper wrapGAppsHook4 gobject-introspection desktop-file-utils ];
  buildInputs = runtimeLibs ++ [ env env.wrappedRuby ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/frogr
    cp -r lib data $out/share/frogr/

    install -Dm755 bin/frogr $out/share/frogr/bin/frogr

    # env.wrappedRuby already resolves GEM_HOME/GEM_PATH for the bundled gems,
    # so the launcher is just that ruby pointed at the app entry point.
    makeWrapper ${env.wrappedRuby}/bin/ruby $out/bin/frogr \
      --add-flags $out/share/frogr/bin/frogr

    for size in 16 24 32 48 64 128; do
      install -Dm644 data/icons/hicolor/''${size}x''${size}/apps/org.gnome.frogr.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/org.gnome.frogr.png
    done
    install -Dm644 data/icons/hicolor/scalable/apps/org.gnome.frogr.svg \
      $out/share/icons/hicolor/scalable/apps/org.gnome.frogr.svg
    install -Dm644 data/icons/hicolor/scalable/apps/org.gnome.frogr-symbolic.svg \
      $out/share/icons/hicolor/symbolic/apps/org.gnome.frogr-symbolic.svg

    install -Dm644 data/manpages/frogr.1 $out/share/man/man1/frogr.1

    runHook postInstall
  '';

  # wrapGAppsHook4 supplies XDG_DATA_DIRS/GI_TYPELIB_PATH; we add the Ruby side.
  preFixup = ''
    gappsWrapperArgs+=(
      --set FROGR_LIB_DIR "$out/share/frogr/lib"
      --set FROGR_DATA_DIR "$out/share/frogr/data"
      --prefix PATH : "${env.wrappedRuby}/bin"
    )
  '';

  meta = with lib; {
    description = "Flickr Remote Organizer for GNOME, ported to Ruby GTK4/Libadwaita";
    homepage = "https://github.com/ruby-gtk-project/frogr-rb";
    license = licenses.gpl3Only;
    mainProgram = "frogr";
    platforms = platforms.linux;
  };
}
