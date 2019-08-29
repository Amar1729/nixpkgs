{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, pythonOlder
, pytest
, cython
, cymem
, darwin
, msgpack-numpy
, msgpack-python
, preshed
, numpy
, murmurhash
, pathlib
, hypothesis
, tqdm
, cytoolz
, plac
, six
, mock
, wrapt
, dill
, blis
, srsly
, wasabi
}:

buildPythonPackage rec {
  pname = "thinc";
  version = "7.1.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "0j2nfzz154j9331gzwa5rmc2f5ljjan728rhgsx6c7jwg323mmsa";
  };

  buildInputs = lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
    Accelerate CoreFoundation CoreGraphics CoreVideo
  ]);

  propagatedBuildInputs = [
   blis
   cython
   cymem
   msgpack-numpy
   msgpack-python
   preshed
   numpy
   murmurhash
   tqdm
   cytoolz
   plac
   six
   srsly
   wrapt
   dill
   wasabi
  ] ++ lib.optional (pythonOlder "3.4") pathlib;


  checkInputs = [
    hypothesis
    mock
    pytest
  ];

  prePatch = ''
    substituteInPlace setup.py \
      --replace "plac>=0.9.6,<1.0.0" "plac>=0.9.6"
  '';

  # Cannot find cython modules.
  doCheck = false;

  checkPhase = ''
    pytest thinc/tests
  '';

  meta = with stdenv.lib; {
    description = "Practical Machine Learning for NLP in Python";
    homepage = https://github.com/explosion/thinc;
    license = licenses.mit;
    maintainers = with maintainers; [ aborsu danieldk sdll ];
    };
}
