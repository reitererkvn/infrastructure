#!/bin/bash
# 1.0s warten, damit der Kernel den Port-Cleanup der Kabelverbindung abschließt
sleep 1.0

# 2. Suche den Pfad des Lightspeed-Dongles (046d:c539)
DONGLE_PATH=$(ls -d /sys/bus/usb/devices/* | while read dev; do
    if [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ]; then
        if [ "$(cat "$dev/idVendor")" = "046d" ] && [ "$(cat "$dev/idProduct")" = "c539" ]; then
            echo "$dev"
            break
        fi
    fi
done)

# 3. Wenn Dongle gefunden -> Hard-Reset durchführen
if [ -n "$DONGLE_PATH" ]; then
    DEV_NAME=$(basename "$DONGLE_PATH")
    echo "$DEV_NAME" > /sys/bus/usb/drivers/usb/unbind
    sleep 0.5
    echo "$DEV_NAME" > /sys/bus/usb/drivers/usb/bind
fi
