{ stdenv, fetchFromGitHub,
callPackage,
autoconf, automake, cmake, gcc, git, gnum4, ocaml, opam, openjdk, perl, pkgconfig, python2, sqlite, which, zlib,
darwin,
withC ? true,
withJava ? true
}:

let
  infer-deps = callPackage ./deps {};
  facebook-clang = callPackage ./clang {
    inherit infer-deps;
    inherit darwin;
  };
in
stdenv.mkDerivation rec {
  pname = "infer";
  version = "0.16.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = "infer";
    rev = "v${version}";
    sha256 = "1fzm5s0cwah6jk37rrb9dsrfd61f2ird3av0imspyi4qyp6pyrm6";
  };

  # TODO - only fetch this is withC == true
  # why am i fetching this if i'm also depending on facebook-clang as a separate pkg?
  #
  # i should fetch this so i can do the linking manually
  # check : can i just fetchSubmodules=true and go from there?
  # 	NO! - not sure why submodules doesnt work, but it doesn't
  # i think i tried that, but it's tough to force that sutff to make?
  facebook-clang-plugins = fetchFromGitHub {
    owner = "facebook";
    repo = "facebook-clang-plugins";
    rev = "36266f6c86041896bed32ffec0637fefbc4463e0";
    sha256 = "1iwpjwjl6p9y0b4s8zcsdwfy8pwik1zv1hl9shwl7k6svkdg58zy";
  };

  case_fail = ./FailingTest.java;
  case_pass = ./PassingTest.java;

  dontUseCmakeConfigure = true;

  doCheck = true;

  depsBuildBuild = [ git ];

  nativeBuildInputs = [ which ];

  buildInputs = [
    autoconf
    automake
    gnum4
    infer-deps
    ocaml
    opam
    perl
    pkgconfig
    python2
    sqlite
    # TODO - include ocamlPackages.utop v2.1.0 for infer-repl
    zlib
  ]
  # infer will need recent gcc or clang to work properly on linux (custom clang depends on libs)
  #++ stdenv.lib.optionals stdenv.isLinux    [ gcc ]
  ++ stdenv.lib.optionals withC             [ cmake facebook-clang ]
  ++ stdenv.lib.optionals withJava          [ openjdk ]
  ;

  postUnpack = ''
    # setup opam stuff
    mkdir -p $out/libexec
    cp -r ${infer-deps}/opam $out/libexec
    export OPAMROOT=$out/libexec/opam
    export OPAMSWITCH='ocaml-variants.4.07.1+flambda'

    eval $(SHELL=bash opam env)
  ''
#  postUnpack = ''
#    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
#    export OPAMSWITCH='ocaml-variants.4.07.1+flambda'
#    export OPAMROOT=$out/libexec/opam
#    mkdir -p $out/libexec
#    pushd $src
#      opam init --bare --no-setup --disable-sandboxing
#      opam switch create $OPAMSWITCH
#      opam install --deps-only infer . --locked
#    popd
#  ''
  + stdenv.lib.optionalString withC ''
    # link facebook clang plugins and the custom clang itself (bit hacky)
    chmod u+w $src
    rm -rf $src/facebook-clang-plugins
    ln -s ${facebook-clang-plugins} $src/facebook-clang-plugins
    chmod -R u+w $src/facebook-clang-plugins

    pushd $src/facebook-clang-plugins/clang > /dev/null
    [[ -h include ]] && rm include
    [[ -h install ]] && rm install
    ln -sfv ${facebook-clang} ./install
    ln -sfv ${facebook-clang}/include ./include
    shasum -a 256 setup.sh src/llvm_clang_compiler-rt_libcxx_libcxxabi_openmp-7.0.1.tar.xz > installed.version
    popd > /dev/null
  ''
  + stdenv.lib.optionalString stdenv.isDarwin ''
    # have to fix SDKROOT (SYSROOT) so clang sees header files (during infer compilation)
    mkdir -p sdkroot
    ln -sfv ${stdenv.lib.getDev stdenv.cc.libc} sdkroot/usr
    export SDKROOT=$(realpath sdkroot)
  '';

  preConfigure = "./autogen.sh";

  configureFlags =
       stdenv.lib.optionals withC       [ "--with-fcp-clang" ]
    ++ stdenv.lib.optionals withC       [ "CLANG_PREFIX=${facebook-clang}" ]
    ++ stdenv.lib.optionals (!withC)    [ "--disable-c-analyzers" ]
    ++ stdenv.lib.optionals (!withJava) [ "--disable-java-analyzers" ]
  ;

  # make test works for full infer: fails to config_tests if either java or c analyzer is disabled
  checkPhase = "make test || make config_tests";

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
