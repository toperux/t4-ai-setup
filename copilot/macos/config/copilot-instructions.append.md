# bash on macOS

The system tools are BSD, not GNU: `sed -i` needs an explicit backup suffix (`sed -i ''`), `grep` has no `-P`, `date` has no `-d`, and `readlink -f` is unreliable — reach for `python3` rather than guessing at flag spellings. `/bin/bash` is 3.2, so a script that has to run there can use no `mapfile`, `declare -A` or `${var^^}`. The default filesystem is case-insensitive, so a case-only rename needs two `git mv` steps. Homebrew's prefix is `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel — resolve it with `brew --prefix` instead of hardcoding either.
