{ stdenv, fetchurl,
# libs required to build clang
cmake, ncurses, perl, python,
# ocaml/opam support, libs for required opam packages
ocaml, opam,
infer-deps, zlib,
#autoconf, automake, git, gnum4, pkgconfig, sqlite, which, zlib,
# Darwin support
xpc }:

stdenv.mkDerivation rec {
  name = "facebook-clang";
  pname = "llvm_clang_compiler-rt_libcxx_libcxxabi_openmp";
  tag = "36266f6c86041896bed32ffec0637fefbc4463e0";
  version = "7.0.1";

  # NOTE! this is just a dep of the facebook-clang-plugins project
  src = fetchurl {
    # this is the clang version used by infer v0.16.0
    url = "https://github.com/facebook/facebook-clang-plugins/raw/${tag}/clang/src/${pname}-${version}.tar.xz";
    sha256 = "06c8mv372rvgs2zq5pwlqyh8wx5pp6zrzbyz1a07ld58vwmc2whk";
  };

  # the srcfile looks like a gzip so nix unpackPhase gets confused
  unpackCmd = "tar -xf $src";

  # want checks in overarching facebook-clang-plugins project
  doCheck = false;
  enableParallelBuilding = true;

  # this needs to be built inside the directory to use hardcoded libc++
  dontUseCmakeBuildDir = true;

  cmakeDir = "../";

  # per original setup.sh, stripping only on darwin (what to do on linux?)
  stripDebugList = [ "bin" "lib" ];
  stripDebugFlags = "-x";

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    #"-DCMAKE_C_FLAGS=$CFLAGS $CMAKE_C_FLAGS"
    #"-DCMAKE_CXX_FLAGS=$CXXFLAGS $CMAKE_CXX_FLAGS"
    "-DLLVM_ENABLE_ASSERTIONS=Off"
    "-DLLVM_ENABLE_EH=On"
    "-DLLVM_ENABLE_RTTI=On"
    "-DLLVM_INCLUDE_DOCS=Off"
    "-DLLVM_TARGETS_TO_BUILD=all"
    # TODO: this is needed for infer (build? runtime?)
    # but i can't get it to build w/out "impure path being linked":
    # /usr/lib/crt1.o is being linked instead of nix glibc/lib/crt1.o
    #"-DLLVM_BUILD_EXTERNAL_COMPILER_RT=On"
  ]
  ++ stdenv.lib.optionals stdenv.isDarwin [
    "-DLLVM_ENABLE_LIBCXX=On"
    #"-DCMAKE_SHARED_LINKER_FLAGS=$LDFLAGS $CMAKE_SHARED_LINKER_FLAGS"
    "-DLLVM_BUILD_LLVM_DYLIB=On"
  ]
  ++ stdenv.lib.optionals stdenv.isLinux [
    #"-DCMAKE_SHARED_LINKER_FLAGS=$LDFLAGS $CMAKE_SHARED_LINKER_FLAGS -lstdc++"
    "-DCMAKE_SHARED_LINKER_FLAGS=-lstdc++"
    "-DCMAKE_C_FLAGS=-s"
    "-DCMAKE_CXX_FLAGS=-s"
  ];

  buildInputs = [
    cmake
    infer-deps
    ncurses
    perl
    python
    # include ocaml+opam so clang builds with opam support
    ocaml
    opam
    zlib
  ]
  #++ stdenv.lib.optionals stdenv.isLinux [ gcc gcc_multi ]
  ++ stdenv.lib.optionals stdenv.isDarwin [ xpc ]
  ;

  outputs = [ "out" ];

  postUnpack = "
    # setup opam stuff
    export OPAMROOT=${infer-deps}/opam
    export OPAM_BACKUP=${infer-deps}/opam.bak
    export OCAML_VERSION='ocaml-variants.4.07.1+flambda'
    export INFER_OPAM_SWITCH=$OCAML_VERSION

    # dumb hack: some opam operations need to write minor build files to opam repo
    chmod u+w ${infer-deps}
    # backup stays around if previous builds have failed: make sure to nuke it
    [[ -d $OPAM_BACKUP ]] && (chmod -R u+w $OPAM_BACKUP && rm -rf $OPAM_BACKUP)
    cp -r $OPAMROOT $OPAM_BACKUP
    chmod -R u+w $OPAMROOT

    eval $(SHELL=bash opam config env --switch=$INFER_OPAM_SWITCH)
  ";

  preConfigure = ''
    cmakeFlagsArray+=(
      -G "Unix Makefiles"
    )

    mkdir -p build && cd build

    # workaround install issue with ocaml llvm bindings and ocamldoc
    mkdir -p docs/ocamldoc/html
  '';
  
  #postBuild = "make ocaml_doc";

  postInstall = "
    # clean up opam build files
    rm -rf $OPAMROOT
    mv $OPAM_BACKUP $OPAMROOT
  ";

  meta = with stdenv.lib; {
    description = "Custom clang for use with infer";
    longDescription = ''
        A custom-built clang to support plugins to clang-analyzer and clang-frontend
    '';
    homepage = "https://github.com/facebook/facebook-clang-plugins";
    license = with licenses; [ bsd3 ];
    maintainers = with maintainers; [ amar1729 ];
    platforms = platforms.all;
  };
}
