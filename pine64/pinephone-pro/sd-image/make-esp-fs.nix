{ pkgs, lib, populateESPCommands, dosfstools, mtools, libfaketime }:

pkgs.stdenv.mkDerivation {
  name = "esp-fs.img";

  nativeBuildInputs = [ dosfstools libfaketime mtools ];

  buildCommand = ''
    img=$out
    (
    mkdir -p ./files
    ${populateESPCommands}
    )

    # Make a crude approximation of the size of the target image.
    # If the script starts failing, increase the fudge factors here.
    numInodes=$(find ./files | wc -l)
    numDataBlocks=$(du -s -c -B 4096 --apparent-size ./files | tail -1 | awk '{ print int($1 * 1.10) }')
    bytes=$((2 * 4096 * $numInodes + 4096 * $numDataBlocks))
    echo "Creating an FAT32 image of $bytes bytes (numInodes=$numInodes, numDataBlocks=$numDataBlocks)"

    truncate -s $bytes $img

    faketime -f "1970-01-01 00:00:01" mkfs.vfat $img

    (cd ./files; mcopy -pvsm -i $img ./* ::)
    fsck.vfat -vn $img
  '';
}

