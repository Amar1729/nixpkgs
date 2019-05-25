{ stdenv, fetchFromGitHub,
callPackage,
cacert,
autoconf, automake, cmake, gcc, git, gnum4, ocaml, opam, openjdk, perl, pkgconfig, python2, sqlite, which, zlib,
gmp, mpfr,
darwin,
withC ? true,
withJava ? true
# , xcodePlatform ? stdenv.targetPlatform.xcodePlatform or "MacOSX"
# , xcodeVer ? stdenv.targetPlatform.xcodeVer or "9.4.1"
# , sdkVer ? stdenv.targetPlatform.sdkVer or "10.10"
, xcodebuild
}:

let
  #sdkName = "${xcodePlatform}${sdkVer}";
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
    fetchSubmodules = true;
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

  # move all/most of these to nativeBuildInputs ?
  depsBuildBuild = [
    autoconf
    automake
    cacert
    gnum4
    git
    ocaml
    opam
    perl
    pkgconfig
    #xcodebuild
  ]
  ++ stdenv.lib.optionals withC             [ cmake ]
  ++ stdenv.lib.optionals withJava          [ openjdk ]
  ;

  nativeBuildInputs = [ which ];

  buildInputs = [
    #infer-deps # for gmp and mpfr
    gmp
    mpfr
    python2
    sqlite
    # TODO - include ocamlPackages.utop v2.1.0 for infer-repl
    zlib
  ]
  # infer will need recent gcc or clang to work properly on linux (custom clang depends on libs)
  #++ stdenv.lib.optionals stdenv.isLinux    [ gcc ]
  ++ stdenv.lib.optionals withC             [ facebook-clang ]
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
    export CLANG_PREFIX=${facebook-clang}
    $src/facebook-clang-plugins/clang/setup.sh -r
  ''
  + stdenv.lib.optionalString (withC && stdenv.isDarwin) ''
    # have to fix SDKROOT (SYSROOT) so clang sees header files (during infer compilation)
    mkdir -p sdkroot
    ln -sfv ${stdenv.lib.getDev stdenv.cc.libc} sdkroot/usr
    export SDKROOT=$(realpath sdkroot)

    # still necessary?
    eval $(SHELL=bash opam env)
  '';

  configureFlags =
       stdenv.lib.optionals withC       [ "--with-fcp-clang" ]
#    ++ stdenv.lib.optionals withC       [ "CLANG_PREFIX=${facebook-clang}" ]
# can't set this here, has to be exported? :/
    ++ stdenv.lib.optionals (!withC)    [ "--disable-c-analyzers" ]
    ++ stdenv.lib.optionals (!withJava) [ "--disable-java-analyzers" ]
  ;

#    #export SDKROOT=${sdkName}
#    export SDKROOT=${darwin.apple_sdk.sdk}
#    echo ${darwin.apple_sdk.sdk}

  # looks like i was bamBOOZled
  # this fuckin sdk doesn't have anything there!
  # SDKROOT=$(xcode-select --print-path)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
  # /nix/store/9jd199393al3ffxrc6q3l2y789airc2l-xcodebuild-0.1.2-pre/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
  # soo ... where tf to find stdio.h ?
  # check out nix's llvm pkg to figure out if they're doing weird patching? idk
#  configurePhase = ''
#    ./autogen.sh
#
#    # try this?
#    #export SYSROOT=${stdenv.lib.getDev stdenv.cc.libc}
#    #export SDKROOT=$SYSROOT
#
#    #export SDKROOT=$(xcode-select --print-path)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
#    echo 'sdkroot:'
#    echo $SDKROOT
#    echo 'stopping:'
#    exit 2
#    ./configure --with-fcp-clang --enable-c-analyzers --disable-java-analyzers
#  '';
  preConfigure = "./autogen.sh";

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
