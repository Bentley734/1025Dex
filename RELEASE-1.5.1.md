# 1025Dex 1.5.1 — Gen3 battler-slot crash fix

Fix `execution.lua:182: attempt to index local 'user' (a number value)`. Gen3 double battles, switching Pursuit and some facility actions pass battler slot numbers instead of objects. Resolve current occupants using the native state API before running modern mechanics. Preserve native absent-actor/end-of-battle cancellation and automatic targeting, without spending PP on cancelled actions.

Validation on official gen1recomp v0.3.89: reproduced the exact crash before the fix; four numeric doubles slots, object/side references, replaced-slot occupants, automatic targeting, Pursuit dispatch, modern move IDs and cancelled actions pass in FireRed, LeafGreen, Ruby, Sapphire and Emerald. Existing production tests pass 833 move dispatches per game, including PP, native presentation, Fairy damage, doubles Ally Switch, Emergency Exit, Skill Link, Fly and recharge. These are engine integration checks, not a complete gameplay playthrough.

Restart after updating. Saves and user options are unchanged.
