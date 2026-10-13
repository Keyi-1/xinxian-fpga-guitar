# Simulation-only recorded-residual reference

Frozen from `fb574a4` to compare the accepted sound with the procedural hammer
experiment. These modules and the old residual table must never be added to a
Gowin production project or included as FPGA ROM assets. Module names have the
`legacy_` prefix, and the table is read only by simulation A/B references.
The table is ignored by Git and reconstructed locally from the baseline commit
by the simulation scripts; it is not a tracked sound asset on this branch.

The experiment's production RTL has no residual table or recorded PCM read.
Contest source/bitstream submissions should exclude this historical test folder.
