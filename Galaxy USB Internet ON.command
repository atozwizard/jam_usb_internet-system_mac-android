#!/bin/zsh

DIR="${0:a:h}"
"$DIR/jam-usb-internet" system
echo
echo "Press any key to close this window."
read -k 1
