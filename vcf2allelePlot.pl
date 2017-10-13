#!/usr/bin/perl

use warnings;
use strict;
use Getopt::Std;

my $program = 'vcf2allelePlot.pl';					#name of script

my %parameters;							#input parameters
my ($infile,$outfile,$gffile,$outprefix);
my $qual = 40;
my $RcmdFile = "vcf2allelePlot.Rcmds";
my $mwsize = 5000;
my $upperH = 0.8;		# upper limit defining heterozygosity (ie <=80% of base calls): problem:A,C .. better to look at pileup file?
my $lwsize = 100000;
my $gffoutfile = "prefix.gff";

getopts('i:o:q:g:w:mh',\%parameters);

if (exists $parameters{"i"}) { $infile = $parameters{"i"}; }
if (exists $parameters{"q"}) { $qual = $parameters{"q"}; }
if (exists $parameters{"g"}) { $gffile = $parameters{"g"}; }
if (exists $parameters{"o"}) { $outfile = $parameters{"o"}; }
elsif (defined $infile) { 
	if ($infile =~ /^(.+)\.\S+?$/m) { $outfile = "$1.calls"; $outprefix = $1; }
	else { $outfile = "$infile.calls"; $outprefix = $1; }
} 
if (exists $parameters{"w"}) { $mwsize = $parameters{"w"}; }


unless (exists $parameters{"i"}) {
	print "\n USAGE: $program -i '<vcf file>'\n\n";
	print   "    -i\tvcf file from mpileup -u + bcftools call -c\n";
	print   "    -q\tminimum phred-scaled quality [$qual]\n";
	print   "    -g\tgff file of annotations [none]\n";
	print   "    -m\tshow mode in non-overlapping sliding windows\n";
	print   "    -h\tshow heterozygosity in non-overlapping sliding windows\n";
	print   "    -w\twindow size [$mwsize bp]\n";
	print 	"    -o\tprefix for outfiles [prefix of vcf file]\n\n";
	exit;
}

open GFFOUT, ">$outprefix.gff" or die "couldn't open $outprefix.gff : $!";


# READ THE GFF OF ANNOTATIONS IF THERE IS ONE

my (%atype,%astart,%aend,%seentype);		# chr will be the keys in these hashes of arrays
my (@chr, @types);
if (defined $gffile) { 
	open GFF, "<$gffile" or die "couldnt open $gffile : $!"; 
	print "\nReading in annotations from $gffile\n";
	while (<GFF>) {
		if (/^(\S+)\s+\S+\s+(\S+)\s+(\d+)\s+(\d+)/m) {
			print GFFOUT $_;
			$seentype{$2}++;
			push (@{$atype{$1}},$2);
			push (@{$astart{$1}},$3);
			push (@{$aend{$1}},$4);			
		}
		else { warn "\n**Unrecognized format for $gffile.**\n\n"; }
			
	}
	close GFF;
	@chr = sort keys %atype;
	@types = sort keys %seentype;
	print "   Found annotations for ".@chr." chromosomes: @chr\n";
	print "   There are ".@types." types of annotation: @types\n";

}


# Extract relevant information for the allele plot 
# and Read in information relevant for the R commands (e.g. which chromosomes are present)
#
open DATA, "<$infile" or die "couldn't open $infile : $!";

open OUT, ">$outfile" or die "couldn't open $outfile : $!";

print OUT "chr\tpos\tREF\tALT\tQUAL\tREFfwd\tREFrev\tALTfwd\tALTrev\tpALT\ttype\n";

print "\nReading and printing data from $infile to $outfile ..\n";

my %chr;
my ($H,$sH,$fH);			# estimate heterozygosity ($H) from the number of high quality point subs ($ps) and high quality length ($l)
my $ps = 0; my $sps = 0; my $fps = 0;	# + short region sH (chr1 200,000..400,000)
my $l = 0; my $sl = 0; my $fl = 0;	# + annotation-filtered fH genome-wide
my $H3; my $ps3 = 0; my $l3 =0;		# + short region sH (chr1 900,000..1,100,000)

while (<DATA>) { 
								# find the lines with data 
	if (/^(\S+)\s+(\d+)\s+\.\s+(\S+)\s+(\S+)\s+(\S+)\s+\.\s+\S+?DP4=(\d+),(\d+),(\d+),(\d+)/m) {
		my $chr = $1;
		my $pos = $2;
		my $ref = $3;
		my $alt = $4;
		my $q = $5;


		my $filter = "no";

		if ($q >= $qual) {	 # keep count of high quality sequence (including invariant sites)
			$l++; 										# genome-wide
			if (($chr eq "chr1") && ($pos > 200000) && ($pos <= 400000)) { $sl++; } 	# 200kb on chr1
			if (($chr eq "chr3") && ($pos > 900000) && ($pos <= 1100000)) { $l3++; } 	# 200kb on chr3

			foreach my $achr (@chr) { 
				if ($chr eq $achr) { 	
					for (my $i=0; $i < @{$astart{$chr}}; $i++) {
						if (($pos > $astart{$chr}[$i]) && ($pos <= $aend{$chr}[$i])) { $filter = "yes"; }		
					}
				}
			}  
			if ($filter eq "no") { $fl++; }
		}		
		if ($alt eq ".") { next; }				# invariant site
			
		
		my $pAlt = ($8+$9)/($6+$7+$8+$9);
		print OUT "$chr\t$2\t$3\t$4\t$5\t$6\t$7\t$8\t$9\t$pAlt\t";
		$chr{$chr}++;					# a hash storing chromosome names and the number of variant sites for each
		my $variant = "snp";				# a non-SNP variant
		unless (($ref =~/^\S$/m) && ($ref =~ /^\S$/m)) { $variant = "indel"; }	
		if ($alt =~ /[A-Z][A-Z]/mi) { $variant = "indel"; }	 	# indels are missed without this
		print OUT "$variant\n";

		if (($variant eq "snp") && ($q>=$qual) && ($pAlt>=0.2) && ($pAlt<=0.8))	{ 		# point sub with 0.2-0.8 allele ratio?
			$ps++; 										# genome-wide
			if (($chr eq "chr1") && ($pos > 200000) && ($pos <= 400000)) { $sps++; } 	# 200kb on chr1
			if (($chr eq "chr3") && ($pos > 900000) && ($pos <= 1100000)) { $ps3++; } 	# 200kb on chr1
			if ($filter eq "no") { $fps++; }
		}
		
	}
}
close OUT;

print "$infile\t$l\t# Length of high quality sequence (q>=$qual)\n";
print "$infile\t$ps\t# Number of high quality point subs (q>=$qual)\n";
print "$infile\t".($ps/$l)."\t# Genomewide heterozygosity (\$ps/\$l)\n";

print "\n$infile\t$fl\t# Length of unannotated sequence (q>=$qual)\n";
print "$infile\t$fps\t# Number of point subs that are unannotated (q>=$qual)\n";
print "$infile\t".($fps/$fl)."\t# Unannotated heterozygosity (\$fps/\$fl)\n";

if ($sl > 0) {
	print "\n$infile\t$sl\t# Length of sequence on chr1 200,000..400,000 (q>=$qual)\n";
	print "$infile\t$sps\t# Number of point subs on chr1 200,000..400,000 (q>=$qual)\n";
	print "$infile\t".($sps/$sl)."\t# Chr1 200kb heterozygosity (\$sps/\$sl)\n";
}

if ($l3 > 0) {
	print "\n$infile\t$l3\t# Length of sequence on chr3 900,000..1,100,000 (q>=$qual)\n";
	print "$infile\t$ps3\t# Number of point subs on chr3 900,000..1,100,000 (q>=$qual)\n";
	print "$infile\t".($ps3/$l3)."\t# Chr3 200kb heterozygosity (\$ps3/\$l3)\n\n";
}


# Print Rcmds to run with R CMD BATCH
open RCMD, ">$RcmdFile" or die "couldn't open $RcmdFile : $!";

print RCMD "
rm(list=ls())
data<-read.table(\"$outfile\",header=T)
attach(data)
head(data)
pdf(\"$outprefix.$mwsize.pdf\")

				# A function for estimating the mode
Mode <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

";
								# add an extra plot for heterozygosity if requested
if (defined $parameters{"h"}) { print RCMD "par(mfrow=c(3,1),cex=0.5)\n";  } 
else { print RCMD "par(mfrow=c(2,1),cex=0.5)\n"; }

foreach my $chr (sort keys %chr) {

	print RCMD "

				# prepare a sliding window vector for estimating mode
x<-ceiling(max(pos[chr==\"$chr\"&QUAL>=40])/100000)
W<-1:((x/($mwsize/1000))*100)*$mwsize-($mwsize/2)
head(W)
tail(W)
modepALTsnp<-0
modepALTindel<-0
diff_snp<-0
err_snp<-0
het_snp<-0

for(i in 1:length(W)) { 
	modepALTsnp[i] <- Mode(pALT[pos>(W[i]-($mwsize/2))&pos<=(W[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]) 
	diff_snp[i] <- sum(pALT[pos>(W[i]-($mwsize/2))&pos<=(W[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]>0.8) 
	err_snp[i] <- sum(pALT[pos>(W[i]-($mwsize/2))&pos<=(W[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]<0.2) 
	het_snp[i] <- sum(pALT[pos>(W[i]-($mwsize/2))&pos<=(W[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"])-err_snp[i]-diff_snp[i]
}
summary(modepALTsnp)
head(cbind(W,modepALTsnp))
tail(cbind(W,modepALTsnp))
head(cbind(W,diff_snp/$mwsize))
head(cbind(W,err_snp/$mwsize))


for(i in 1:length(W)) { modepALTindel[i] <- Mode(pALT[pos>(W[i]-($mwsize/2))&pos<=(W[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"indel\"]) }


				# MAKE SEPARATE STACKED PLOTS FOR SNPs AND INDELS
				# SNPs
plot(c(0,max(W)),c(0,1),main=\"$infile: $chr freq of alternate alleles\",sub=\"SNPs Q$qual+\",xlab=\"position\",xaxt=\"n\",ylab=\"allele ratio\",ylim=c(0,1),xlim=c(1,max(pos[chr==\"$chr\"])),type = \"n\")
points(pos[chr==\"$chr\"&QUAL>=$qual&type==\"snp\"],pALT[chr==\"$chr\"&QUAL>=40&type==\"snp\"],pch=20,col=\"black\")
axis(1, xaxp=c(0, signif(max(pos[chr==\"$chr\"]),3), 20))
abline(h=0.5)
abline(h=mean(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]),col=\"orange\")


## ESTIMATE LOH regions using LOH window size ($lwsize)
				# prepare a sliding window vector for estimating LOH regions
lx<-ceiling(max(pos[chr==\"$chr\"&QUAL>=40])/100000)
lW<-1:((lx/($lwsize/1000))*100)*$lwsize-($lwsize/2)
head(lW)
tail(lW)
ldiff_snp<-0
lerr_snp<-0
lhet_snp<-0

for(i in 1:length(lW)) { 
	ldiff_snp[i] <- sum(pALT[pos>(lW[i]-($lwsize/2))&pos<=(lW[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]>0.8) 
	lerr_snp[i] <- sum(pALT[pos>(lW[i]-($lwsize/2))&pos<=(lW[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]<0.2) 
	lhet_snp[i] <- sum(pALT[pos>(lW[i]-($lwsize/2))&pos<=(lW[i]+($mwsize/2))&chr==\"$chr\"&QUAL>=$qual&type==\"snp\"])-lerr_snp[i]-ldiff_snp[i]
}
options(scipen=999)
LOHstarts_$chr<-lW[lhet_snp/$lwsize<0.0005]-($lwsize/2)
LOHends_$chr<-lW[lhet_snp/$lwsize<0.0005]+($lwsize/2)

LOHstarts_$chr
LOHends_$chr


\n";

	if (defined $parameters{'m'}) { showmode($chr,"snp"); }	# show mode if requested
	if (defined $parameters{'g'}) { annotate($chr); }	# show annotations on SNP plot if requested 
	
	if (defined $parameters{'h'}) { 			# make a new plot of H if requested
								# legend format for 3 plots per page
		print RCMD "par(xpd=T)\n";	# do print legend outside the plot	
		print RCMD "legend(0,-0.16,c(round(mean(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]),3),0.5),lty=c(1,1),col=c(\"orange\",\"black\"),title=\"mean\",bty=\"n\")\n";
		print RCMD "par(xpd=F)\n";	# don't print annotations outside the plot

		showH($chr,"snp");
		annotate($chr); 				# show annotations on H plot if requested 
	}			
	else { 							# legend format for 2 plots per page
		print RCMD "legend(0,0.15,c(round(mean(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"snp\"]),3),0.5),lty=c(1,1),col=c(\"orange\",\"black\"),title=\"mean\",bty=\"n\")\n"; 
	}					
	
	print RCMD "
				# INDELs
plot(c(0,max(W)),c(0,1),main=\"$infile: $chr freq of alternate alleles\",sub=\"Indels Q$qual+\",xlab=\"position\",ylab=\"allele ratio\",xaxt=\"n\",ylim=c(0,1),xlim=c(1,max(pos[chr==\"$chr\"])),type = \"n\")	
points(pos[chr==\"$chr\"&QUAL>=$qual&type==\"indel\"],pALT[chr==\"$chr\"&QUAL>=40&type==\"indel\"],pch=20,col=\"black\")	
axis(1, xaxp=c(0, signif(max(pos[chr==\"$chr\"]),3), 20))
abline(h=0.5)
abline(h=mean(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"indel\"]),col=\"orange\")
legend(0,-0.16,c(round(mean(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"indel\"]),3),0.5),lty=c(1,1),col=c(\"orange\",\"black\"),title=\"mean\",bty=\"n\")
";

	if (defined $parameters{'m'}) { showmode($chr,"indel"); }	# show mode if requested
	if (defined $parameters{'g'}) { annotate($chr); }		# show annotations on INDEL plot if requested (in progress)
	
	print RCMD "rm(W,modepALTsnp,modepALTindel)\n";			# CLEAN UP


}

close RCMD;

# RUN THE R COMMANDS WITH OUTPUTS GOING OUT TO THE DEFAULT FILE NAMES

print "Running $RcmdFile commands in R ..\n";
`R CMD BATCH $RcmdFile`;
`mv vcf2allelePlot.Rcmds.Rout $outprefix.Rout`;		# save R input and output for future reference
`mv vcf2allelePlot.Rcmds $outprefix.Rcmds`;		# save R input and output for future reference
print "Done. R output is in $RcmdFile".".Rout and plots are in $outprefix.pdf\n\n";


# READ IN R OUTPUT TO EXTRACT THE LOH REGIONS TO PRINT IN GFF FORMAT

open ROUT, "<$outprefix.Rout" or die "couldn't open $outprefix.Rout : $!";

my $results;
print "LOH regions:\n";
while (<ROUT>) { $results .= $_; }
#print $results;
while ($results =~ /LOHstarts_(chr[a-z0-9]+).*?(\s+\d+\s+.*?)LOHends_(chr[a-z0-9]+).*?\s+/imsg) { 
	my $chr = $1;
	my $starts = $2;
	my $ends = $3;

	my (@starts,@ends);
	while ($starts =~/\s+(\d+)/g) { push (@starts,$1); push (@ends,$1+$lwsize); }

#	print "chromosome: $chr\nstarts: @starts\nends: @ends\n";



	my (@jstarts,@jends);
	my $prevend = -1; my $jstart = "none";			# in progress: need to join into continuos blocks
	for (my $i=0; $i<@starts; $i++) {
#		print "$chr\t$starts[$i] .. $ends[$i]\t$jstart\t[$prevend]\n";
		if ($jstart eq "none") {			# a new LOH block 
			push (@jstarts, $starts[$i]); 
			$jstart = $starts[$i]; 
			$prevend = $ends[$i];
			next;
		}
		if ($prevend == $starts[$i]) { 			# continuing a LOH block
			$prevend = $ends[$i]; 
			next; 
		}
		else {						# end of a LOH block
			print "LOHblock: $chr\t$jstart\t$prevend\n";		# problem: 1st entry gets mistaken for a block
			print GFFOUT "$chr\tvcf2allelePlot.pl\tLOH\t$jstart\t$prevend\t.\t+\t.\tLOHregion. Windowsize=$lwsize; snp heterozygosity < 0.0005\n";		

			push (@jends,$prevend);
			$jstart = $starts[$i];
			push (@jstarts, $starts[$i]); 
			$prevend = $ends[$i];
		}
	}
	my $i = @starts-1;
	print "LOHblock: $chr\t$jstart\t$prevend\n";		# last LOH block
	print GFFOUT "$chr\tvcf2allelePlot.pl\tLOH\t$jstart\t$ends[$i]\t.\t+\t.\tLOHregion. Windowsize=$lwsize; snp heterozygosity < 0.0005\n";
	push (@jends,$ends[$i]);
	
}

close ROUT;
close GFFOUT;

# SUBROUTINES 

sub annotate {
						# annotate the plot with slightly transparent colored rectangles
	my $chr = shift;

	for (my $i=0; $i<@{$astart{$chr}}; $i++) {
		my $j;				# use a number from 1 to n for type color	
		for ($j=0; $j<@types; $j++) { if ($atype{$chr}[$i] eq $types[$j]) { $j += 1; last; } }	
			
		print RCMD "rect($astart{$chr}[$i],0,$aend{$chr}[$i],1,col=rainbow(".@types.",alpha=0.3)[$j],border=rainbow(".@types.",alpha=0.3)[$j])\n"; 	

	}
	print RCMD "par(xpd=T)\n";	# do print legend outside the plot	


	for (my $j=1; $j<=@types; $j++) {
		print RCMD "legend(W[100],-0.15-($j/20),lty=1,legend=\"$types[$j-1]\",col=rainbow(".@types.",alpha=0.3)[$j],bty=\"n\")\n";	
	}
	print RCMD "par(xpd=F)\n";	# don't print annotations outside the plot
}	

sub showmode {
	my $chr = shift;
	my $type = shift;
	print RCMD "par(xpd=T)\n";	# do print legend outside the plot	
	print RCMD "lines(W,modepALT$type,col=\"green\")\n";
	print RCMD "legend(W[60],-0.16,Mode(pALT[chr==\"$chr\"&QUAL>=$qual&type==\"$type\"]),lty=1,col=\"green\",title=\"mode\",bty=\"n\")\n";
	print RCMD "par(xpd=F)\n";	# don't print annotations outside the plot	
}

sub showH {
	my $chr = shift;
	my $type = shift;

	print RCMD "
my<-max((het_$type+diff_$type+err_$type)/$mwsize)
plot(c(0,max(W)),c(0,max((het_$type+diff_$type+err_$type)/$mwsize)),type='n',ylab=\"No.sites per $mwsize\",xlab=\"position\",main=\"$infile: $chr sliding window ($mwsize) of heterozygosity, homozygous diffs and error\",sub=\"$type Q$qual+\",xaxt=\"n\")
axis(1, xaxp=c(0, signif(max(pos[chr==\"$chr\"]),3), 20))
\n";
	print RCMD "lines(W,diff_$type/$mwsize,col=\"blue\")\n"; # No. of sites per window size (ie does not control for missing data
	print RCMD "lines(W,het_$type/$mwsize,col=\"red\")\n";
	print RCMD "lines(W,err_$type/$mwsize,col=\"grey\")\n";

	print RCMD "par(xpd=T)\n";	# do print legend outside the plot	
	print RCMD "legend(W[60],my,c(\"diff_$type\",\"het_$type\",\"err_$type\"),lty=c(1,1,1),col=c(\"blue\",\"red\",\"grey\"),bty=\"n\")\n";
	print RCMD "par(xpd=F)\n";	# don't print annotations outside the plot	

}				

