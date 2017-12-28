#!/bin/bash
set -e

# Setup architectures, library name and other vars + cleanup from previous runs
ARCHS=("armv7" "armv7s" "arm64" "i386" "x86_64")
SDKS=("iphoneos" "iphoneos" "iphoneos" "macosx" "macosx")
LIB_NAME="libevent-2.0.21-stable"
SCRIPT_DIR=$(dirname "$0")
OUTPUT_DIR="${SCRIPT_DIR}/.."
HEADER_DEST_DIR="${OUTPUT_DIR}/include/ios/libevent"
LIB_DEST_DIR="${OUTPUT_DIR}/lib/ios/libevent"

TEMP_DIR="/tmp/build_libevent_ios"
TEMP_LIB_PATH="${TEMP_DIR}/${LIB_NAME}"

PLATFORM_LIBS=("libz.tbd") # Platform specific lib files to be copied for the build
PLATFORM_HEADERS=("zlib.h") # Platform specific header files to be copied for the build
PLATFORM_DEPENDENCIES_DIR="${TEMP_DIR}/platform"

rm -rf "${TEMP_LIB_PATH}*" "${LIB_NAME}"


###########################################################################
# Unarchive library, then configure and make for specified architectures

# Copy platform dependency libs and headers
copy_platform_dependencies()
{
   ARCH=$1; SDK_PATH=$2;

   PLATFORM_DEPENDENCIES_DIR_H="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/include"
   PLATFORM_DEPENDENCIES_DIR_LIB="${PLATFORM_DEPENDENCIES_DIR}/${ARCH}/lib"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_H}"
   mkdir -p "${PLATFORM_DEPENDENCIES_DIR_LIB}"

   for PLIB in "${PLATFORM_LIBS[@]}"; do
      cp "${SDK_PATH}/usr/lib/$PLIB" "${PLATFORM_DEPENDENCIES_DIR_LIB}"
   done

   for PHEAD in "${PLATFORM_HEADERS[@]}"; do
      cp "${SDK_PATH}/usr/include/$PHEAD" "${PLATFORM_DEPENDENCIES_DIR_H}"
   done
}

# Unarchive, setup temp folder and run ./configure, 'make' and 'make install'
configure_make()
{
   ARCH=$1; GCC=$2; SDK_PATH=$3;
   LOG_FILE="${TEMP_LIB_PATH}-${ARCH}.log"
   tar xfz "${LIB_NAME}.tar.gz";

   pushd . > /dev/null; cd "${LIB_NAME}";

   copy_platform_dependencies "${ARCH}" "${SDK_PATH}"

   # Configure and make

   if [ "${ARCH}" == "i386" ];
   then
      HOST_FLAG=""
   else
      HOST_FLAG="--host=arm-apple-darwin11"
   fi

   mkdir -p "${TEMP_LIB_PATH}-${ARCH}"

   ./configure --disable-shared --enable-static --disable-debug-mode ${HOST_FLAG} \
   --prefix="${TEMP_LIB_PATH}-${ARCH}" \
   CC="${GCC} " \
   LDFLAGS= \
   CFLAGS=" -arch ${ARCH} -isysroot ${SDK_PATH}" \
   CPPLAGS=" -arch ${ARCH} -isysroot ${SDK_PATH}" &> "${LOG_FILE}"

   make -j2 &> "${LOG_FILE}"; make install &> "${LOG_FILE}";

   popd > /dev/null; rm -rf "${LIB_NAME}";
}

for ((i=0; i < ${#ARCHS[@]}; i++));
do
   echo "configure and make libevent for arch ${ARCHS[i]}..."

   SDK_PATH=$(xcrun -sdk ${SDKS[i]} --show-sdk-path)
   GCC=$(xcrun -sdk ${SDKS[i]} -find clang)
   configure_make "${ARCHS[i]}" "${GCC}" "${SDK_PATH}"
done

# Combine libraries for different architectures into one
# Use .a files from the temp directory by providing relative paths
mkdir -p "${LIB_DEST_DIR}"
create_lib()
{
   LIB_SRC=$1; LIB_DST=$2;
   echo "creating fat library from ${LIB_SRC} to ${LIB_DST}..."

   LIB_PATHS=( "${ARCHS[@]/#/${TEMP_LIB_PATH}-}" )
   LIB_PATHS=( "${LIB_PATHS[@]/%//${LIB_SRC}}" )
   lipo ${LIB_PATHS[@]} -create -output "${LIB_DST}"
}
LIBS=("libevent.a" "libevent_core.a" "libevent_extra.a" "libevent_pthreads.a")
for DEST_LIB in "${LIBS[@]}";
do
   create_lib "lib/${DEST_LIB}" "${LIB_DEST_DIR}/${DEST_LIB}"
done

# Copy header files + final cleanups
mkdir -p "${HEADER_DEST_DIR}"
cp -R "${TEMP_LIB_PATH}-${ARCHS[0]}/include"/* "${HEADER_DEST_DIR}"
rm -rf "${TEMP_DIR}"

echo "libevent is built and copied!"
