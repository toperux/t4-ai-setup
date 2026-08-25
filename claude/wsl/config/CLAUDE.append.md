# bash on WSL

Keep working copies on the Linux filesystem (`~/src`), not under `/mnt/c`. Paths on `/mnt/c` cross the Windows filesystem bridge, which is roughly an order of magnitude slower for the many small reads a build, a `git status` or a recursive grep performs. Windows executables are callable by name (`explorer.exe`, `code.exe`) but expect Windows paths — convert with `wslpath -w` instead of passing a POSIX path straight through.
