#!/bin/zsh

DIR="${0:a:h}"
"$DIR/jam-usb-internet" system-recover
echo
echo "Press any key to close this window."
read -k 1
