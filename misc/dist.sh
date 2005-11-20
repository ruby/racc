#!/bin/sh

rm -rf tmp
mkdir tmp
cd tmp

# racc, raccrt
cvs -Q export -r`echo V$version | tr . -` -d racc-$version racc
cd racc-$version
    make bootstrap lib/racc/parser-text.rb doc
    rm -r doc web bits fastcache
cd ..
mkdir -p raccrt-$version/lib/racc
mv racc-$version/lib/racc/parser.rb     raccrt-$version/lib/racc
mv racc-$version/ext                    raccrt-$version
cp racc-$version/setup.rb               raccrt-$version
cp racc-$version/README.*               raccrt-$version
cp racc-$version/COPYING                raccrt-$version
tar czf $ardir/racc/racc-$version.tar.gz racc-$version
tar czf $ardir/raccrt/raccrt-$version.tar.gz raccrt-$version

# -all
mkdir -p racc-$version-all/packages
cp racc-$version/setup.rb racc-$version-all
cp racc-$version/README.* racc-$version-all
mv racc-$version          racc-$version-all/packages/racc
mv raccrt-$version        racc-$version-all/packages/raccrt
tar czf $ardir/racc/racc-$version-all.tar.gz racc-$version-all

cd ..
rm -rf tmp
