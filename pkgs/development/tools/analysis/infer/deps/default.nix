{ stdenv,
cacert,
autoconf, automake, gnum4, gmp, mpfr, ocaml, opam, perl, pkgconfig, python2, sqlite, which, zlib, }:

stdenv.mkDerivation rec {
  name = "infer-deps";
  version = "0.16.0"; # version-locked to infer

  src = ./.; # this is a trivial package - just opam deps for infer!

  opamlock = ./opam.lock;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ which ];

  buildInputs = [
    autoconf
    automake
    gnum4
    gmp
    mpfr
    ocaml
    opam
    perl
    pkgconfig
    sqlite
    zlib
  ];

  installPhase = ''
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

    export OPAMROOT=$out/opam
    export OPAMYES=1
    export OCAML_VERSION='ocaml-variants.4.07.1+flambda'
    export INFER_OPAM_SWITCH=$OCAML_VERSION

    mkdir -p $OPAMROOT
    opam init --bare --no-setup --disable-sandboxing
    opam switch create $INFER_OPAM_SWITCH
    eval $(SHELL=bash opam config env --switch=$INFER_OPAM_SWITCH)
    opam install --deps-only infer . --locked
  '';

  meta = with stdenv.lib; {
    description = "Opam dependencies for infer";
    longDescription = ''
      Dependencies opam/ocaml for static analysis tool infer.
      Provided as a separate package to keep builds clean, since
      both infer and facebook-clang-plugins depend on this.
    '';
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ amar1729 ];
    platforms = platforms.all;
  };
}
