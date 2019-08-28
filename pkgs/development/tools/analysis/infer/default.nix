{ stdenv, fetchFromGitHub,
cacert,
autoconf, automake, cmake, gcc, git, gmp, gnum4, mpfr, ocaml,
opam, openjdk, perl, pkgconfig, python2, sqlite, which, zlib,
withC ? false,
withJava ? true
}:

# c support doesnt work yet
assert withC == false;
assert (withC || withJava);

stdenv.mkDerivation rec {
  pname = "infer";
  version = "0.17.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = "infer";
    rev = "v${version}";
    sha256 = "1qfhgc85hm6wwknfs36m030ah3fkb6wcyj3kxm4v1yi2dpm3g3bw";
  };

  case_pass = ./PassingTest.java;
  case_fail = ./FailingTest.java;

  dontUseCmakeConfigure = true;

  doCheck = true;

  depsBuildBuild = [
    autoconf
    automake
    git
    gnum4
    ocaml
    opam
    perl
    pkgconfig
    zlib
  ];

  nativeBuildInputs = [ which ];

  buildInputs = [
    gmp
    mpfr
    python2
    sqlite
  ]
  # infer will need recent gcc or clang to work properly on linux (custom clang depends on libs)
  #++ stdenv.lib.optionals stdenv.isLinux    [ gcc ]
  ++ stdenv.lib.optionals withC             [ cmake ]
  ++ stdenv.lib.optionals withJava          [ openjdk ]
  ;

  postUnpack = ''
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

    # setup opam stuff
    export OPAMROOT=$out/opamroot
    export OPAMYES=1

    substituteInPlace source/build-infer.sh --replace \
        '--bare --no-setup' \
        '--bare --no-setup --disable-sandboxing'
    ./source/build-infer.sh --only-setup-opam --yes
    opam install utop
    eval $(SHELL=bash opam env)
  '';

  # todo - c (clang) support will need some patches in postUnpack here

  preConfigure = "./autogen.sh";

  configureFlags =
       stdenv.lib.optionals withC       [ "--with-fcp-clang" ]
    ++ stdenv.lib.optionals (!withC)    [ "--disable-c-analyzers" ]
    ++ stdenv.lib.optionals (!withJava) [ "--disable-java-analyzers" ]
  ;

  checkPhase = if (withC && withJava) then "make test" else "true";

  postInstall = 
    if (withJava) then ''
      $out/bin/infer --fail-on-issue -- javac ${case_pass}
      $out/bin/infer --fail-on-issue -- javac ${case_fail} || test $? -eq 2
    ''
    else "true";

  meta = with stdenv.lib; {
    description = "A static analyzer for Java, C, C++, and Objective-C";
    longDescription = ''
        A tool written in OCaml by Facebook for static analysis.
        See homepage or https://github.com/facebook/infer for more information.

        Note: building java analyzers requires downloading some GPL-licensed components.
    '';
    homepage = "https://fbinfer.com";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ amar1729 ];
    platforms = platforms.all;
  };
}
