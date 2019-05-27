{ stdenv, fetchFromGitHub, fetchgit,
cacert,
autoconf, automake, cmake, gcc, git, gnum4, ocaml, opam, openjdk, perl, pkgconfig, python2, sqlite, which, zlib,
gmp, mpfr,
darwin,
withC ? true,
withJava ? true
# , xcodePlatform ? stdenv.targetPlatform.xcodePlatform or "MacOSX"
# , xcodeVer ? stdenv.targetPlatform.xcodeVer or "9.4.1"
# , sdkVer ? stdenv.targetPlatform.sdkVer or "10.10"
}:

stdenv.mkDerivation rec {
  pname = "infer";
  version = "0.16.0";
  name = "${pname}-${version}";

#  src = fetchFromGitHub {
#    owner = "facebook";
#    repo = "infer";
#    #rev = "4a91616390c058382c703f47653adfaecd31a7d7";
#    rev = "v${version}";
#    sha256 = "1c96rpj1j3q69dalgydqmmvh26lvvb977nngqngq7qw4mz002zic";
#    #fetchSubmodules = withC;
#  };

# hash is 18marcyh8525nb4k46xg9lnd5wcimacpsfsacqz92rg19h67077j
# {
#   "url": "https://github.com/facebook/infer",
#   "rev": "4a91616390c058382c703f47653adfaecd31a7d7",
#   "date": "2019-04-23T05:04:32-07:00",
#   "sha256": "18marcyh8525nb4k46xg9lnd5wcimacpsfsacqz92rg19h67077j",
#   "fetchSubmodules": true
# }

  # TODO - only fetch this is withC == true
  # setting submodules to true doesn't work since nix doesn't update submodules (???)
  # so i can't cd into the dir, or access it with ${facebook-clang-plugins}
  # so i don't know how tf to reach it ...
#  facebook-clang-plugins = fetchFromGitHub {
#    owner = "facebook";
#    repo = "facebook-clang-plugins";
#    rev = "36266f6c86041896bed32ffec0637fefbc4463e0";
#    sha256 = "1iwpjwjl6p9y0b4s8zcsdwfy8pwik1zv1hl9shwl7k6svkdg58zy";
#  };

  src = fetchgit {
    url = "https://github.com/facebook/infer.git";
    rev = "v0.16.0";
    sha256 = "18marcyh8525nb4k46xg9lnd5wcimacpsfsacqz92rg19h67077j";
    fetchSubmodules = withC;
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
  ++ stdenv.lib.optionals (withC && stdenv.isDarwin) [
    darwin.libobjc
    darwin.apple_sdk.libs.xpc
    # clang needs CoreFoundation to build, but i don't think this will work until 10.12 sdk hits?
    # possibly related
    # https://github.com/NixOS/nixpkgs/issues/55655
    #darwin.cf-private
    #darwin.apple_sdk.frameworks.CoreFoundation
  ]
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
  #++ stdenv.lib.optionals withC             [ facebook-clang ]
  ;

  postUnpack = ''
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    mkdir -p $out/libexec
    export OPAMYES=1
    export OPAMROOT=$out/libexec/opam
    export OPAMSWITCH='ocaml-variants.4.07.1+flambda'
    pushd $src
      opam init --bare --no-setup --disable-sandboxing
      opam switch create $OPAMSWITCH
      opam install --deps-only infer . --locked
    popd
  ''
#  + stdenv.lib.optionalString withC ''
#    export CLANG_PREFIX=${facebook-clang}
#    $src/facebook-clang-plugins/clang/setup.sh -r
#  ''
    #[[ -d $src/facebook-clang-plugins ]] && rm -r $src/facebook-clang-plugins
    #ln -sfv ${facebook-clang-plugins} $src/facebook-clang-plugins
  + stdenv.lib.optionalString withC ''
    CLANG_TMP_DIR=$TMPDIR $src/facebook-clang-plugins/clang/setup.sh
  ''
  + stdenv.lib.optionalString (withC && stdenv.isDarwin) ''
    # have to fix SDKROOT (SYSROOT) so clang sees header files (during infer compilation)
    mkdir -p sdkroot
    ln -sfv ${stdenv.lib.getDev stdenv.cc.libc} sdkroot/usr
    export SDKROOT=$(realpath sdkroot)
  '' + ''
    eval $(opam env)
  '';

  preConfigure = "./autogen.sh";

  configureFlags =
       stdenv.lib.optionals withC       [ "--with-fcp-clang" ]
#    ++ stdenv.lib.optionals withC       [ "CLANG_PREFIX=${facebook-clang}" ]
# can't set this here, has to be exported? :/
    ++ stdenv.lib.optionals (!withC)    [ "--disable-c-analyzers" ]
    ++ stdenv.lib.optionals (!withJava) [ "--disable-java-analyzers" ]
  ;

# incorrect sdkroots:
#   export SDKROOT=${sdkName}
#   export SDKROOT=${darwin.apple_sdk.sdk}
#   echo ${darwin.apple_sdk.sdk}
#   SDKROOT=$(xcode-select --print-path)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

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
