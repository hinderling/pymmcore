#!/bin/bash

set -e -x

test -n "$BOOST_VERSION" || BOOST_VERSION=1_72_0
test -n "$PARALLEL" || PARALLEL=-j2

cd /


curl -LO https://dl.bintray.com/boostorg/release/${BOOST_VERSION//_/.}/source/boost_$BOOST_VERSION.tar.gz
tar xzf boost_$BOOST_VERSION.tar.gz
pushd boost_$BOOST_VERSION
./bootstrap.sh
./b2 --with-system --with-thread --with-date_time link=static runtime-link=shared cxxflags="-fPIC -fvisibility=hidden"
popd


git clone https://github.com/swig/swig.git
pushd swig
git checkout rel-4.0.1
curl -LO https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz
./Tools/pcre-build.sh
./autogen.sh
./configure
make $PARALLEL
make install
popd


# NUMPY_VERSIONS contains alternating ABI tags and NumPy versions.
# Convert it to an associative array.
numpy_versions=($NUMPY_VERSIONS)
declare -A numpy_version_map
abitags=() # To preserve ordering
for ((i=0; i<${#numpy_versions[@]}; i+=2)); do
    abitag=${numpy_versions[i]}
    numpy_version=${numpy_versions[i+1]}

    abitags+=($abitag)
    numpy_version_map[$abitag]=$numpy_version
done


cd /io
for abitag in ${abitags[@]}; do
    numpy_version=${numpy_version_map[$abitag]}
    pybin=/opt/python/$abitag/bin

    # Avoid altering NumPy compile+link (-fvisibility=hidden will break it)
    export CFLAGS=
    export LDFLAGS=
    $pybin/pip install --upgrade pip
    $pybin/pip install --upgrade setuptools wheel numpy==${numpy_version}

    rm -rf build
    export CFLAGS="-fvisibility=hidden -Wno-deprecated -Wno-unused-variable"
    export LDFLAGS="-Wl,--strip-debug" # Sane file size
    $pybin/python setup.py build_ext -I/boost_$BOOST_VERSION -L/boost_$BOOST_VERSION/stage/lib $PARALLEL
    $pybin/python setup.py build
    $pybin/python setup.py bdist_wheel
done


# Update ABI tag
cd /io
compgen -G "dist/*.whl" # Fail if none built
mkdir -p wheelhouse
for wheel in dist/*.whl; do
    auditwheel show $wheel
    auditwheel repair $wheel -w wheelhouse
done


# Sanity check
cd /
for abitag in ${abitags[@]}; do
    pybin=/opt/python/$abitag/bin
    $pybin/pip install pymmcore --no-index -f /io/wheelhouse
    $pybin/python -m pymmcore
done
