#!/usr/bin/perl -w
use Cwd 'abs_path';
use File::Basename;
use File::Spec;
use File::Temp;
my $rundir = dirname(abs_path($0));

use  Scalar::Util qw(looks_like_number);

#ChangeLog 2014-07-02 
#   filter HETATM record from the model files, otherwise proq3 score.linuxxxx
#   may fail
#ChangeLog 2016-05-27
#   For proq3, those scores below 0 and above 1 should not be ignored, the way
#   to merge them with pcons score are chagned accordingly
#

my $usage = "
usage $0 stage [stage ...]

stage can be all, stage1, stage2
";
my $exec_proq3 = "/data3/software/proq3/run_proq3.sh";
my $exec_pcons = "/var/www/pcons/bin/pcons.linux";
my $CASP_TS_DIR = "/var/www/pcons/CASP12/TS";
my $CASP_QA_DIR = $rundir;
my $needle = "$rundir/my_needle_static";
my $cmd = "";

my @to_email_list = (
    "models\@predictioncenter.org",
    "nanjiang.shu\@gmail.com");

# my @to_email_list = (
#     "nanjiang.shu\@gmail.com");

my @stagelist = ();
my $numArgs = $#ARGV+1;
if($numArgs < 1) {
    print "$usage\n";
    exit;
}
if(@ARGV){#{{{
    my $i = 0;
    while($ARGV[$i]) {
        if($ARGV[$i] eq "-h" || $ARGV[$i] eq "--help" ) {
            print "$usage\n";
            exit;
        } else {
            push @stagelist, $ARGV[$i];
            $i += 1;
        }
    }
}#}}}

my $date = localtime();

print "\nStart $0 at $date\n\n";

chdir($rundir);
my $stage = "";

foreach $stage(@stagelist){

    my $casp_model_nr = "";
    my $stage_str = ""; # string to get tarball, e.g. T0762.stage1.3D.srv.tar.gz T0762.3D.srv.tar.gz
    if ($stage eq "stage1"){
        $casp_model_nr = 1;
        $stage_str = ".$stage";
    }elsif($stage eq "stage2"){
        $casp_model_nr = 2;
        $stage_str = ".$stage";
    }elsif($stage eq "all"){
        $casp_model_nr = 3;
        $stage_str = "";
    }else{
        next;
    }
    print "\n$stage\n\n";
    chdir($stage);

    my $WORKDIR="$rundir/$stage";

    $date = localtime();
    my @job_folders=();
    opendir(DIR,"$rundir/$stage");
    my @folders=readdir(DIR);
    closedir(DIR);
    foreach my $folder(@folders) {
        if($folder=~/^T\d+$/ || $folder=~/^T\d+-D1$/ && (-d "$folder" || -l "$folder")) {
            push(@job_folders,$folder);
        }
    }
    foreach my $folder(reverse sort @job_folders) {
        print "Folder: $folder\n";
        my $tarball = "$WORKDIR/$folder$stage_str.3D.srv.tar.gz";
        print "Tarball: $tarball\n";
        #next;
#         if ($folder !~ "T0884"){
#             next;
#         }

        my $targetseq = "$CASP_TS_DIR/$folder/sequence";
        if ($folder =~ /-D1$/){
            my $origfolder = $folder;
            $origfolder =~ s/-D1$//g;
            $targetseq = "$CASP_TS_DIR/$origfolder/sequence";
        }
        if (! -s $targetseq){
            print "targetseq $targetseq does not exist. Ingore\n";
            exit;
        }

        my $seq = `cat $targetseq`;
        chomp($seq);
        my $seqlength = length($seq);

        my $outdir = "$WORKDIR/proq3/$folder";
        if (! -d $outdir){
            `mkdir -p $outdir`;
        }

        my $targetseq_in_fasta = "$WORKDIR/proq3/$folder/sequence.fa";
        open(OUT, ">$targetseq_in_fasta");
        print OUT ">$folder\n";
        print OUT $seq."\n";
        close(OUT);

        my $modellistfile = "$WORKDIR/proq3/$folder/pcons.input";
        `find $WORKDIR/$folder/ -type f -name "*TS[0-9]" > $modellistfile`;
        `find $WORKDIR/$folder/ -type f -name "*TS[0-9]*-D1" >> $modellistfile`;
        `$rundir/filter_HETATM.sh -l $modellistfile`; #added 2014-07-02


        if (-s $modellistfile){
            $cmd = "$exec_proq3 -fasta $targetseq_in_fasta -l $modellistfile -outpath $outdir ";
            $date = localtime();
            print "[$date]: $cmd\n";
            `$cmd`;
            $date = localtime();
            `echo $date > $outdir/FINISHED`;
        }

        # run pcons
        # Due to limited number of models in stage1, +100 models from pcons.net
        # are included to calculate the pcons score.
        if ($stage eq "stage1"){
            # for stage1, add also the pcons.net emsembles to it to get better
            # pcons score statistics
            `find $CASP_TS_DIR/$folder/models/modeller/ -type f -name "*.pdb" >> $modellistfile`;
        }
        my $pcons_outfile = "$WORKDIR/proq3/$folder/pcons.output";
        if (! -s $pcons_outfile){
            print "$exec_pcons -i $modellistfile -L $seqlength -casp -A\n";
            `$exec_pcons -i $modellistfile -L $seqlength -casp -A > $pcons_outfile`;
        }

        if (! -s $pcons_outfile){
            print "$pcons_outfile does not exist. pcons failed \n";
            next;
        }
        my ($pcons_score,$local_quality)=read_QA($pcons_outfile);
        my %pcons_score=%{$pcons_score};
        my %local_quality=%{$local_quality};

        print "Generating CASP12 outputs for models ...\n";
        my $casp_reg_code = "5450-4562-0389";
        my $casp_target_id = $folder;
        my $targetseq_fa = "$WORKDIR/proq3/$folder/sequence.fasta.fasta";


        my @modelnamelist = keys(%pcons_score);
        my $out_datfile = "$WORKDIR/proq3/$folder/pcomb.dat";
        open (DAT, ">$out_datfile");

        foreach my $modelname (@modelnamelist){
            if($modelname =~ /pcons.*pdb/){
                # ignore pcons.net emsembles, the should not be included in the
                # QA models
                next;
            }


            my $proq3file = "$WORKDIR/proq3/$folder/$modelname.proq3.global";
            my $proq3resfile = "$WORKDIR/proq3/$folder/$modelname.proq3.local";

            if ($modelname !~ /.pdb$/){
                $proq3file = "$WORKDIR/proq3/$folder/$modelname.pdb.proq3.global";
                $proq3resfile = "$WORKDIR/proq3/$folder/$modelname.pdb.proq3.local";
            }
            if(-e $proq3file && -e $proq3resfile && defined($pcons_score{$modelname}) && defined($local_quality{$modelname})) {
                # read in proq3 global prediction
                my $proq3_s = "";
                my $tmp_proq3_s = `cat $proq3file | tail -n 1 | awk '{print \$4}'`;
                chomp($tmp_proq3_s);
                if (looks_like_number($tmp_proq3_s)){
                    $proq3_s = $tmp_proq3_s;
                }
                # read in proq3 local prediction
                #==================
                my $proq3res_str = `cat $proq3resfile | awk '/^[^P]/ {printf("%s ", \$4)}'`;
                chomp($proq3res_str);
                my @proq3res_score = split(/\s+/, $proq3res_str);
                my $num_res_proq3 = scalar(@proq3res_score);

                my %proq3res_dict = ();
                if ($num_res_proq3 == $seqlength){
                    for (my $i = 0 ; $i < $num_res_proq3; $i++){
                        $proq3res_dict{$i} = $proq3res_score[$i];
                    }
                }else{
                # if the model length is not equivalent to the target length,
                # do sequence alignment and get residue index mapping
                    my $aln_target_model_file = "$WORKDIR/proq3/$folder/$modelname.aln";
                    my $modelseq_fa =  "$WORKDIR/proq3/$folder/$modelname.fasta";
                    $cmd = "$needle $targetseq_fa $modelseq_fa -m 1 -o $aln_target_model_file  ";
                    print "$cmd\n";
                    `$cmd`;
                    my $alnseq_target = "";
                    my $alnseq_model = "";
                    my $length_alnseq_target = 0;
                    my $length_alnseq_model = 0;

                    my $IS_ALN_SUCCESS = 0;
                    if (-e $aln_target_model_file){
                        $alnseq_target = `cat $aln_target_model_file | grep -v "^>" | head -n 1`;
                        $alnseq_model = `cat $aln_target_model_file | grep -v "^>" | tail -n 1`;
                        chomp($alnseq_target);
                        chomp($alnseq_model);
                        $length_alnseq_target = length($alnseq_target);
                        $length_alnseq_model = length($alnseq_model);
                        if ($length_alnseq_target == $length_alnseq_model && $length_alnseq_target == $seqlength){
                            $IS_ALN_SUCCESS = 1;
                        }
                    }
                    print "alnseq_target=$alnseq_target\n\n";
                    if ($IS_ALN_SUCCESS){
                        my $cntmodelseq = 0;
                        for (my $i = 0 ; $i < $length_alnseq_target; $i++){
                            if (substr($alnseq_target, $i, 1) eq substr($alnseq_model, $i, 1)){
                                $proq3res_dict{$i} = $proq3res_score[$cntmodelseq];
                                $cntmodelseq += 1;
                            }elsif(substr($alnseq_model, $i, 1) ne "-"){
                                $cntmodelseq += 1;
                            }
                        }
                    }else{
                        print "$folder, $modelname, target - model alignment failed\n";
                    }
                }

                #==================

                # get global pcomb score
                if ($proq3_s eq "nan" || $proq3_s eq ""){
                    #if got wired proq3 score, recalculate it from the local
                    #proq3 score
                    my $sum = 0;
                    foreach my $score(@proq3res_score){
                        # the proq3 score can be negative or larger than 1
                        if(looks_like_number($score)){
                            $sum += $score;
                        }
                    }
                    $proq3_s = $sum/$seqlength;
                    `awk -v score=$proq3_s '{print \$1, score, \$3, \$4}' $proq3file > $proq3file.recalculated`; 
                }

                my @pcons_local_score =  @{$local_quality{$modelname}};

                my $num_res_pcons = scalar(@pcons_local_score);

                my $pcons_s = $pcons_score{$modelname};
                my $pcomb_global = $pcons_s * 0.8 + $proq3_s * 0.2; # global pcomb score
                if (looks_like_number($pcomb_global)){

                    if ($pcomb_global < 0.0){
                        $pcomb_global = 0.0;
                    }elsif($pcomb_global > 1.0){
                        $pcomb_global = 1.0;
                    }
                    # convert pcomb_global in the real format x.xxx
                    $pcomb_global = sprintf("%.3f",$pcomb_global);
                }else{
                    $pcomb_global = 'X';
                }


                if ($num_res_proq3 != $num_res_pcons){
                    print "num_res_pcons ($num_res_pcons) != num_res_proq3 ($num_res_proq3)\n";
#                     next;
                }

                # get local pcomb scores
                my @newlist = ();
                for (my $i = 0 ; $i < $num_res_pcons; $i++){
                    my $s_pcons = $pcons_local_score[$i];

                    my $s_proq3 ;
                    if (defined($proq3res_dict{$i})){
                        $s_proq3 = $proq3res_dict{$i};
                    }else{
                        $s_proq3 = -1;
                    }

                    my $s_pcomb ; #local pcomb score
                    if($s_pcons eq "X" ) {
                        print "$folder, $stage, $modelname, s_pcons[$i]=$s_pcons, s_proq3[$i] = $s_proq3\n";
                        if ($s_proq3 ne ''){
                            $s_pcomb = S2d($s_proq3);
                        }else{
                            $s_pcomb = "X";
                        }
                    } else {
                        $s_pcomb = S2d(0.8*d2S($s_pcons)+0.2*$s_proq3);
                    }

                    # fix the bug 2016-05-14, so that the pcomb value will be
                    # in real number format x.x, not 15, The QA model for T0862
                    # and T0863 has been rejected by the CASP 12 server due to
                    # this error
                    if ($s_pcomb ne 'X'){
                        # finally, for any non 'X' pcomb score, set it as 0 if
                        # it is negative
                        if ($s_pcomb < 0.0){
                            $s_pcomb = 0.0;
                        }
                        $s_pcomb = sprintf("%.3f",$s_pcomb);
                    }
                    push(@newlist, $s_pcomb);
                }
                print DAT "$modelname $pcomb_global ". join(" ", @newlist) . "\n";
            }
        }
        close(DAT);

        my $out_mailfile = "$WORKDIR/proq3/$folder/pcomb.mail";
        open (MAIL, ">$out_mailfile");
        print MAIL "PFRMAT QA\n";
        print MAIL "TARGET $casp_target_id\n";
        print MAIL "AUTHOR $casp_reg_code\n";
        print MAIL "METHOD Pcomb\n";
        print MAIL "MODEL $casp_model_nr\n";
        print MAIL "QMODE 2\n";
        close(MAIL);
        # fixed the bug 2014-05-12, try to filter emsembles from pcons.net to
        # the QA output file
        `sort -k2,2rg $out_datfile | grep -v "pcons.*pdb" | awk '{for(i=1;i<=NF;i++){printf("%s ",\$i); if(i%50==0){printf("\\n")}}printf("\\n")}'>> $out_mailfile`;
        `echo END >> $out_mailfile`;

        if ($stage eq "all"){ # we do not send the result for the merged tarball
            next;
        }

        foreach my $to_email(@to_email_list)
        {
            my $tagfile = "$WORKDIR/proq3/$folder/casp_prediction_emailed.$to_email";

            my $prediction_file = "$WORKDIR/proq3/$folder/pcomb.mail";

            next if (! -e $prediction_file);

            my $emailed_prediction_file = "$WORKDIR/proq3/$folder/pcomb.mail.$to_email";
            my $isSendMail = 1;
            #if no change has been made to prediction_file, set isSendMail to false
            if (-e $emailed_prediction_file){
                my $diff = `diff $prediction_file $emailed_prediction_file`;
                if ($diff eq "" ){
                    $isSendMail = 0;
                }
            }

            if (-f $tarball && -M $tarball > 2.0){
                print "$tarball older than 2 days, Do not email results.\n";
                $isSendMail = 0;
            }

            if ($isSendMail){
                my $title = $casp_target_id;
                print "mutt -s \"$title\" \"$to_email\"  < $prediction_file"."\n";
                `mutt -s \"$title\" \"$to_email\"  < $prediction_file`;
                `/bin/cp -f $prediction_file $emailed_prediction_file`;
                $date = localtime();
                `echo $date >>  $tagfile`;
            }
        }
    }
    chdir($rundir);
}
sub read_QA{#{{{
    my $file=shift;
    my $start=0;
    my $key="";
    my $global_quality=0;
    my @local_quality=();
    my %global_quality=();
    my %local_quality=();
    open(FILE,$file);
    while(<FILE>)
    {
        if($start)
        {
            chomp;
            my @temp=split(/\s+/);
            last if(not(defined($temp[0])));
            #if($temp[0]=~/[A-Z]/ && length($temp[0])>1)
            # bug solved in Read_QA, 2014-05-06, model name may contains only
            # lower letter change [A-Z] to [A-Za-z]
            if($temp[0]=~/[A-Za-z]/ && length($temp[0])>1)
            {
                if(scalar(@local_quality)>0)
                {
                    $global_quality{$key}=$global_quality;
                    @{$local_quality{$key}}=@local_quality;
                }
                last if(/^END/);
                $key=$temp[0];
                #$key=~s/\.pdb$//g;
                $global_quality=$temp[1];
                @local_quality=@temp[2..$#temp];
            }
            else
            {
                @local_quality=(@local_quality,@temp);
            }
        }
        $start=1 if(/^QMODE 2/);
    }

    
    #foreach my $key(keys(%global_quality))
    #{
    #   my $size=scalar(@{$local_quality{$key}});
    #   print "$key $global_quality{$key} $size\n";
    #   
    #}
    return({%global_quality},{%local_quality});
}#}}}

# sub d2S#{{{
# {
#     my $rmsd=shift;
#     return 1/sqrt(1+$rmsd*$rmsd/9);
# }#}}}

sub d2S{  #changed on 2014-05-15 according to bjorn
    my $rmsd=shift;
    return 1/(1+$rmsd*$rmsd/9);
}

sub S2d#{{{
{
    my $S=shift;
    my $d0=3;
    my $rmsd=0;
    $rmsd=15; # for CASP we cap the distance at 15 angstroms
    if($S>0.03846) # this is the S score for 15 angstroms
    {
        if($S>=1)
        {    
            $rmsd=0;
        }
        else
        {
            $rmsd=sqrt(1/$S-1)*$d0;
        }
    }
    return $rmsd;
}#}}}
