{ stdenv, fetchurl,
# libs required to build clang
cmake, ncurses, perl, python, zlib,
# ocaml/opam support, libs for required opam packages
ocaml, opam,
infer-deps,
# Darwin support
darwin
}:

let
  # prebuild patch
  err_ret_local_block = fetchurl {
    url = "https://github.com/facebook/facebook-clang-plugins/raw/36266f6c86041896bed32ffec0637fefbc4463e0/clang/src/err_ret_local_block.patch";
    sha256 = "15q8hygphvnwvnh4lc98cm80ixkk00pbgna5azmrrpvw5x4llvrg";
  };

  # prebuild patch
  mangle_suppress_errors = fetchurl {
    url = "https://github.com/facebook/facebook-clang-plugins/raw/36266f6c86041896bed32ffec0637fefbc4463e0/clang/src/mangle_suppress_errors.patch";
    sha256 = "1myv2spsj9qqs2ny9fv0ipski3fjnnzamv7dfki6hp3k160nhc3k";
  };

  # clang patch - applied after build
  attr_dump_cpu_cases_compilation_fix = fetchurl {
    url = "https://github.com/facebook/facebook-clang-plugins/raw/36266f6c86041896bed32ffec0637fefbc4463e0/clang/src/attr_dump_cpu_cases_compilation_fix.patch";
    sha256 = "1ph6hw66sp31a4mg5rp99mghgdgj0qb30gxnih06chczg1gxynd5";
  };
in
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

  patchFlags = [ "--batch" "-p" "2"  ];

  # pre-build patches
  patches = [
    err_ret_local_block
    mangle_suppress_errors
  ]
  ++ stdenv.lib.optionals stdenv.isDarwin [
    ./codesign.patch
  ];

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

  # to get rid of infer-deps, we'll have to install a few ocaml libs into this drv?
  # or figure out a way to depend on parts of caller drv
  # maybe we can just isntall ocaml+ctypes in a common place to infer
  # and then let infer handle the rest of it
  # or we can do the whole thing in infer

  # change this to nativeBuildInputs also?
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
  # will we need corefoundation or any cf-private stuff?
  ++ stdenv.lib.optionals stdenv.isDarwin [ darwin.libobjc darwin.apple_sdk.libs.xpc ]
  ;

  # try manually specifying outputs so we get flags properly made up in infer drv
  outputs = [ "bin" "include" "lib" "libexec" "share" ];

  postUnpack = "
    # setup opam stuff
    mkdir -p $out/libexec
    cp -r ${infer-deps}/opam $out/libexec
    export OPAMROOT=$out/libexec/opam
    export OPAMSWITCH='ocaml-variants.4.07.1+flambda'

    eval $(SHELL=bash opam env)
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
    # patch the built clang
    pushd $out/include
    patch --batch -p 2 < ${attr_dump_cpu_cases_compilation_fix}
    popd
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
