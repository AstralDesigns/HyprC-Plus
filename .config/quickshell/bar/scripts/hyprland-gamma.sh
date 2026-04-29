#!/bin/bash
# Gamma adjustment — relative delta, matches GJS original which called
# 'hyprctl hyprsunset gamma -10' and 'hyprctl hyprsunset gamma +10'.
# hyprctl needs an explicit '+' prefix to treat a positive number as a
# relative increase; without it some builds treat it as an absolute set.

delta="${1:-10}"

# Add '+' prefix to bare positive numbers so the sign is unambiguous
if [[ "$delta" =~ ^[0-9] ]]; then
    delta="+${delta}"
fi

hyprctl hyprsunset gamma "$delta"
