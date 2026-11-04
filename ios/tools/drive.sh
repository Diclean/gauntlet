#!/bin/bash
# Small helper to drive the demo app on the "Gauntlet v2" simulator.
AD=/Users/mathys/.t3/userdata/device/targets/t3-9a8bca72fe22093336a53326/agent-device
cd /Users/mathys/.t3/projects/iphone-app-for-friends/ios || exit 1

ref_for() {
    local out
    out=$($AD snapshot -i 2>/dev/null)
    local ref
    ref=$(echo "$out" | grep -i -F "\"$1\"" | grep -E "\[(button|text|other)\]" | head -1 | grep -o '@e[0-9]*' | head -1)
    if [ -z "$ref" ]; then
        ref=$(echo "$out" | grep -i -F "\"$1," | grep -E "\[(button|text|other)\]" | head -1 | grep -o '@e[0-9]*' | head -1)
    fi
    echo "$ref"
}

press_label() {
    local ref
    ref=$(ref_for "$1")
    if [ -z "$ref" ]; then
        echo "NO REF FOR: $1"
        $AD snapshot -i 2>/dev/null | head -40
        return 1
    fi
    $AD press "$ref" --settle >/dev/null 2>&1
    echo "pressed $ref ($1)"
}

shot() {
    $AD screenshot "screenshots/$1" --pixel-density 3 2>&1 | tail -1
}

case "$1" in
    press) press_label "$2" ;;
    shot)  shot "$2" ;;
    snap)  $AD snapshot -i 2>/dev/null | head -60 ;;
    relaunch) $AD open com.mathys.dares --launch-args="-demo" --relaunch >/dev/null 2>&1; echo relaunched ;;
    relaunch-quiet) $AD open com.mathys.dares --launch-args="-demo" --launch-args="-demo-sim-delay" --launch-args="600" --relaunch >/dev/null 2>&1; echo relaunched-quiet ;;
esac
