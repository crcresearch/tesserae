#!/usr/bin/env perl

#
# This is a template for how Tesserae scripts should begin.
#
# Please fill in documentation notes in POD below.
#
# Don't forget to modify the COPYRIGHT section as follows:
#  - name of the script where it says "The Original Code is"
#  - your name(s) where it says "Contributors"
#

=head1 NAME

lsa.samples.pl - create training set for lsa

=head1 SYNOPSIS

lsa.samples.pl [options] LANG

=head1 DESCRIPTION

Searches for a corpus of texts in the language subdirectory specified by LANG. Breaks each
text up into a series of equally-sized samples to use as input data for the LSA search
tool.  Two series of samples are created from each text: one, B<source> to use as the 
documents to be matched, and another, B<target> to use as the queries.  By default the 
source samples are larger than the target samples, but you can change this using the 
I<--source> and I<--target> options at the command line.  

Training is done on the source set using I<lsa.train.py>.

=head1 OPTIONS AND ARGUMENTS

=over

=item I<LANG>

Language to process.

=item B<--source> I<SIZE>

Create 'source' samples (training set) using approximately I<SIZE> characters of the 
original text for each sample.

=item B<--target> I<SIZE>

Create 'target' samples (query set) using approximately I<SIZE> characters of the 
original text for each sample.

=item B<--help>

Print usage and exit.

=back

=head1 KNOWN BUGS

=head1 SEE ALSO

=head1 COPYRIGHT

University at Buffalo Public License Version 1.0.
The contents of this file are subject to the University at Buffalo Public License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://tesserae.caset.buffalo.edu/license.txt.

Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.

The Original Code is lsa.samples.pl.

The Initial Developer of the Original Code is Research Foundation of State University of New York, on behalf of University at Buffalo.

Portions created by the Initial Developer are Copyright (C) 2007 Research Foundation of State University of New York, on behalf of University at Buffalo. All Rights Reserved.

Contributor(s): Chris Forstall, Walter Scheirer

Alternatively, the contents of this file may be used under the terms of either the GNU General Public License Version 2 (the "GPL"), or the GNU Lesser General Public License Version 2.1 (the "LGPL"), in which case the provisions of the GPL or the LGPL are applicable instead of those above. If you wish to allow use of your version of this file only under the terms of either the GPL or the LGPL, and not to allow others to use your version of this file under the terms of the UBPL, indicate your decision by deleting the provisions above and replace them with the notice and other provisions required by the GPL or the LGPL. If you do not delete the provisions above, a recipient may use your version of this file under the terms of any one of the UBPL, the GPL or the LGPL.

=cut

use strict;
use warnings;

#
# Read configuration file
#

# modules necessary to read config file

use Cwd qw/abs_path/;
use File::Spec::Functions;
use FindBin qw/$Bin/;

# read config before executing anything else

my $lib;

BEGIN {

	# look for configuration file
	
	$lib = $Bin;
	
	my $oldlib = $lib;
	
	my $pointer;
			
	while (1) {

		$pointer = catfile($lib, '.tesserae.conf');
	
		if (-r $pointer) {
		
			open (FH, $pointer) or die "can't open $pointer: $!";
			
			$lib = <FH>;
			
			chomp $lib;
			
			last;
		}
									
		$lib = abs_path(catdir($lib, '..'));
		
		if (-d $lib and $lib ne $oldlib) {
		
			$oldlib = $lib;			
			
			next;
		}
		
		die "can't find .tesserae.conf!\n";
	}	
}

# load Tesserae-specific modules

use lib $lib;
use Tesserae;
use EasyProgressBar;

# modules to read cmd-line options and print usage

use Getopt::Long;
use Pod::Usage;

# load additional modules necessary for this script

use Storable qw(nstore retrieve);
use File::Basename;
use File::Path qw(mkpath rmtree);

# approximate size of samples in characters

my %size = (target => 500, source => 1000);
my $help;

# check for cmd line options

GetOptions(
	'target=i' => \$size{target},
	'source=i' => \$size{source},
	'help'     => \$help
	);

# print usage if the user needs help
	
if ($help) {

	pod2usage(1);
}

# language database

my $file_lang = catfile($fs{data}, 'common', 'lang');
my %lang = %{retrieve($file_lang)};

# stem dictionary

my %stem;
my $lang = shift(@ARGV) or pod2usage(1);

# global variables hold working data

my @token;
my @phrase;

# read files to process from cmd line args

my @texts = @{Tesserae::get_textlist($lang)};

for my $name (@texts) {
		
	# load text from v3 database
	
	my $base = catfile($fs{data}, 'v3', $lang, $name, $name);

	@token = @{retrieve("$base.token")};
	@phrase = @{retrieve("$base.phrase")}; 
	
	#
	# process each file as both target and source
	#
	
	print STDERR "$name\n";
	
	for my $mode (qw/source target/) {

		print STDERR "$mode:\n";

		my @bounds;
	
		# create/clean output directory

		my $opdir = catfile($fs{data}, 'lsa', $lang, $name, $mode);
		
		rmtree($opdir);
		mkpath($opdir);
						
		# write samples
				
		my $pr = ProgressBar->new(scalar(@phrase));
		
		my $ndigit = length($#phrase);
		
		for my $i (0..$#phrase) {
		
			$pr->advance();
			
			my $opfile = catfile($opdir, sprintf("%0${ndigit}i", $i));
			
			open (FH, ">:utf8", $opfile) || die "can't create $opfile: $!";
			
			my ($sample, $lbound, $rbound) = sample($size{$mode}, $i);
			
			print FH $sample;
			push @bounds, [$lbound, $rbound];
			
			close FH;
		}
		
		my $file_bounds = catfile($fs{data}, 'lsa', $lang, $name, "bounds.$mode");
		
		nstore \@bounds, $file_bounds;
	}
}

#
# subroutines
#

sub sample {

	my ($smin, $unit_id) = @_;
		
	my @tokens;
	my $size = 0;
	
	for (@{$phrase[$unit_id]{TOKEN_ID}}) {
	
		if ($token[$_]{TYPE} eq "WORD") {
		
			push @tokens, $_;
			$size += length($token[$_]{FORM});
		}
	}
	
	my $lpos = $phrase[$unit_id]{TOKEN_ID}[0];
	my $rpos = $phrase[$unit_id]{TOKEN_ID}[-1];
	
	while (($size < $smin) and ($rpos-$lpos < $#token)) {
		
		ADDL:
		while ($lpos > 0) {
		
			$lpos --;
			
			next ADDL unless $token[$lpos]{TYPE} eq "WORD";
			
			push @tokens, $lpos;
			
			$size += length($token[$lpos]{FORM});
			
			last ADDL;
		}
		
		ADDR:
		while ($rpos < $#token) {
		
			$rpos ++;
			
			next ADDR unless $token[$rpos]{TYPE} eq "WORD";
			
			push @tokens, $rpos;
			
			$size += length($token[$rpos]{FORM});
			
			last ADDR;
		}
	}
	
	my @stems;
	
	for (@tokens) {
	
		push @stems, @{stems($token[$_]{FORM})};
	}
		
	my $sample = join(" ", @stems)  . "\n";
		
	return ($sample, $lpos, $rpos);
}

sub stems {

	my $form = shift;
	
	my @stems;
	
	if (defined $stem{$form}) {
	
		@stems = @{$stem{$form}};
	}
	else {
	
		@stems = ($form);
	}
	
	return \@stems;
}