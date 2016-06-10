#!/bin/bash

exec_cmd(){
    echo "$*"
    eval "$*"
}
rundir=`dirname $0`

cd $rundir

OPT1="--exclude=~* --exclude=*~ --exclude=.*.sw[mopn]"
OPT2="--exclude=.*.lock"

exec_cmd "/usr/bin/rsync -auz  ./ $OPT1 $OPT2 x_nansh@triolith.nsc.liu.se:/proj/bioinfo/users/share/CASP12/QA_Pcomb3/"
