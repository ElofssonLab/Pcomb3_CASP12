#!/bin/bash

exec_cmd(){
    echo "$*"
    eval "$*"
}
rundir=`dirname $0`

cd $rundir

outpath=QA_Pcomb_CASP12


if [ ! -d $outpath ];then
    mkdir -p $outpath
fi

for folder in all stage1 stage2;do
    exec_cmd "/usr/bin/rsync -auz  --include=proq3 --include=proq3/T*/ --include=proq3/T*/pcomb.mail --exclude=** $folder/ $outpath/$folder/"
done

outname=`basename $outpath`
exec_cmd "tar -czf $outname.tar.gz $outpath/"

# copy to pcons.net
#1. load profile
if [ -f $outname.tar.gz ];then
    . /home/nanjiang/.bash_profile
    exec_cmd "/usr/bin/rsync -auz -e ssh $outname.tar.gz nanjiang.shu@pcons1.scilifelab.se:/var/www/html/pcons/CASP12/QA/"
fi
