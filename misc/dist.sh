#!/bin/sh

datadir=$HOME/share
wcdir=$HOME/c
ardir=$HOME/var/archive

rm -rf tmp
mkdir tmp
cd tmp

# racc, raccrt
cvs -Q export -r`echo V$version | tr . -` -d racc-$version racc
mkdir -p raccrt-$version/lib/racc
(cd racc-$version; rm -rf bits fastcache web Bison-Parser)
(cd racc-$version/lib/racc; make)
(cd racc-$version; make doc)
mv racc-$version/lib/racc/parser.rb  raccrt-$version/lib/racc
mv racc-$version/ext                 raccrt-$version
cp racc-$version/README.*            raccrt-$version
cp $datadir/setup.rb racc-$version
cp $datadir/setup.rb raccrt-$version
cp $datadir/LGPL racc-$version/COPYING
cp $datadir/LGPL raccrt-$version/COPYING
tar czf $ardir/racc/racc-$version.tar.gz racc-$version
tar czf $ardir/raccrt/raccrt-$version.tar.gz raccrt-$version

# -all
rm */setup.rb */COPYING
mkdir -p racc-$version-all/packages
mv racc-$version          racc-$version-all/packages/racc
mv raccrt-$version        racc-$version-all/packages/raccrt
cp $datadir/setup.rb      racc-$version-all
cp $datadir/README.setup  racc-$version-all/README
tar czf $ardir/racc/racc-$version-all.tar.gz racc-$version-all

cd ..
rm -rf tmp
