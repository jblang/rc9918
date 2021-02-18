## Introduction to selected z88dk Libraries
This file describes some z88dk compatible libraries.

## Preparation
The libraries can be compiled using the following command lines in Linux, with the `+target` modified to be relevant to your machine, from the relevant library sub-directory. e.g. for any `library`.

```bash
zcc +target -lm -x -SO3 --opt-code-size -clib=sdcc_ix --max-allocs-per-node400000 @library.lst -o library
mv library.lib ./target/lib/newlib/sdcc_ix
zcc +target -lm -x -SO3 --opt-code-size -clib=sdcc_iy --max-allocs-per-node400000 @library.lst -o library
mv library.lib ./target/lib/newlib/sdcc_iy
zcc +target -lm -x -SO3 --opt-code-size -clib=new @library.lst -o library
mv library.lib ./target/lib/newlib/sccz80
```
The resulting `library.lib` file should be moved to `~/library/target/lib/newlib/sdcc_ix` or `~/library/target/lib/newlib/sdcc_iy` or `~/library/target/lib/newlib/sccz80` respectively, as noted above.

## Installation

Then, the `z88dk-lib` function is used to install for the desired target. e.g. for the time library on the yaz180 machine.

```bash
cd ..
z88dk-lib +rc2014 tms
```

Some further examples of `z88dk-lib` usage.

+ libraries list help
```bash
z88dk-lib
```
+ list 3rd party libraries already installed for the rc2014 target
```bash
z88dk-lib +rc2014
```
+ remove the `libname1` `libname2` ... libraries from the rc2014 target, -f for no nagging about deleting files.
```bash
z88dk-lib +rc2014 -r -f libname1 libname2 ...
```

## Usage
Once installed, the libraries can be linked against on the compile line by adding `-llib/target/library` and the include file can be found with `#include <lib/target/library.h>`.
