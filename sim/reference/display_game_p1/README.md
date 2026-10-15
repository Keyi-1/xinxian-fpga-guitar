The palette is frozen from merge commit
`efdcf24277ab560b527ef1b24ab4348f77c9ae61`, with only the module name changed.
`check_result.py --p1` checks that exact provenance using `git show`.

The display wrapper duplicates the current integration with only its module
name and palette instance type changed. It keeps the production scanner, CDC,
FFT, bands, curve RAM/renderer, chart and UI in the equivalence test. The gate
runner also substitutes this frozen palette into its whole-top RTL reference.
No production audio, visual coefficients, ROMs or scan latencies are changed.
