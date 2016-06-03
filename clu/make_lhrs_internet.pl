#!/m1/shared/bin/perl -w

# Creates internet holdings for OCLC Local Holdings Records pilot

use strict;
use lib "/usr/local/bin/voyager/perl";
use MARC::Batch;
use UCLA_Batch; #for UCLA_Batch::safenext to better handle data errors

my $argc = @ARGV;
if ($argc != 2) {
  print "Usage: $0 data_input_file marc_input_file\n";
  exit 1;
}

my $datafile = $ARGV[0];
my $marcfile = $ARGV[1];

# Read file of mfhd_id and oclc values into hash for later use
my %data;
open(DATA, $datafile) || die "Can't open $datafile: $!\n";
while (<DATA>) {
  chomp; #remove trailing newline
  my ($mfhd_id, $oclc) = split(/\t/);
  $data{$mfhd_id} = $oclc;
}

# UTF-8, not MARC-8
open OUT, '>:utf8', "lhrs_internet.mrc" or die "Cannot open output file: $!\n";

# For creating fake 001 fields
my $seqno = 0;

my $batch = MARC::Batch->new('USMARC', $marcfile);
$batch->strict_off();

# Loop thru bib records, creating LHRs as appropriate
while (my $bibrecord = UCLA_Batch::safenext($batch)) {
  # Only create LHRs for bib records with 856 $xUCLA
  my @f856s = $bibrecord->field('856');
  foreach my $f856 (@f856s) {
    my $f856x = $f856->subfield('x');
    if ($f856x && $f856x eq 'UCLA') {

      $seqno++;

      # Get bib 001 (bib_id) and use it to look up OCLC#
      my $bib_id = $bibrecord->field('001')->data();
      my $oclc = $data{$bib_id};

      # Create new holdings record
      my $mfhd = MARC::Record->new();

      # Set leader with values for serial internet holdings
      $mfhd->leader('00000ny   22000002n 4500');

      # Unicode
      $mfhd->encoding('UTF-8');

      # Add fake 001 field to keep OCLC happy
      $mfhd->append_fields(MARC::Field->new('001', 'CLULHR'.$seqno));

      # Add 007 from bib, or create default
      my $f007 = $bibrecord->field('007');
      if (! $f007) {
        $f007 = MARC::Field->new('007', 'tu');
      }
      $mfhd->append_fields($f007);
 
      # Add 008 for serial internet holdings
      my $yymmdd = get_yymmdd();
      my $f008 = MARC::Field->new('008', $yymmdd . '0u    8   0001uu   0' . $yymmdd);
      $mfhd->append_fields($f008);
 
      # Add 035 field with OCLC#
      my $f035 = MARC::Field->new('035', '', '', a=>'(OCoLC)'.$oclc);
      $mfhd->append_fields($f035);

      # Add 852 field
      my $f852 = MARC::Field->new('852', '', '', a=>'CLU', b=>'in');
      $mfhd->append_fields($f852);

      # Add 856 field from bib record, after removing $x
      $f856->delete_subfield(code => 'x');
      $mfhd->append_fields($f856);

      # Write new holdings record to new file
      print OUT $mfhd->as_usmarc();

    } # if 856 $x UCLA
  } # foreach f856
}

# Clean up
close DATA;
close OUT;

exit 0;

sub get_yymmdd {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year-=100; # add 1900, subtract 2000, to get current 2-digit year for 2000-2099
  if ( $year <= 9 ) {
    $year = "0".$year;
  }
  $mon+=1;    # localtime gives $mon as 0..11
  if ( $mon <= 9 ) {
    $mon = "0".$mon;
  }
  if ( $mday <= 9 ) {
    $mday = "0".$mday;
  }
  return $year.$mon.$mday;
}
