#!/bin/bash

# clean bad acc predictions

filelist=$(for stage in all stage1 stage2; do find $stage -name "sequence.*.acc" -size -2c ; done)
for file in $filelist; do 
    dirname=`dirname $file`; echo $dirname; rm -f $dirname/sequence.fasta.*; 
done

for stage in all stage1 stage2; do 
    find $stage -name "*.acc" -size -2c -print0 | xargs -0 rm -f
done

# clean bad proq3 predictions
for stage in all stage1 stage2; do  
    for file in $(find $stage -name "*.proq3.local"); do 
        content=$(cat $file  | awk '{if (NF != 4) {print} }')
        if [ "$content" != "" ];then
            stemname=${file%.local}
            rm -f  $stemname.local $stemname.global
        fi
    done
done

for stage in all stage1 stage2; do  
    for file in $(find $stage -name "*.proq3.global"); do 
        nline=$(cat $file  | wc -l )
        if [ $nline -lt 2  ];then
            stemname=${file%.global}
            rm -f  $stemname.local $stemname.global
        fi
    done
done

for stage in all stage1 stage2; do  
    for file in $(find $stage -name "*.proq3.local"); do 
        nline=$(cat $file  | wc -l )
        if [ $nline -lt 2  ];then
            stemname=${file%.local}
            rm -f  $stemname.local $stemname.global
        fi
    done
done
