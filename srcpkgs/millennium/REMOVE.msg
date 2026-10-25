If you ran millennium-setup, remove the symlinks it left in your home
directory as each user that enabled it:

  rm -f ~/.steam/steam/ubuntu12_32/libXtst.so.6 \
        ~/.steam/steam/ubuntu12_64/libXtst.so.6 \
        ~/.steam/steam/ubuntu12_64/libmillennium_hhx64.so
