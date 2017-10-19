#!/m1/shared/bin/perl -w

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

# Write UTF-8 LHRs to file
open OUT, '>:utf8', "jstor_jacs_lhrs.mrc" or die "Cannot open output file: $!\n";

# Read file of Voyager holdings records and create OCLC LHR for each
my $batch = MARC::Batch->new('USMARC', $marcfile);
while (my $record = UCLA_Batch::safenext($batch)) {
  my $fld;
  my @flds;
  my $link_val; # for 85x/86x linking
  my $new_val = 1;
  my $tag;
  # Initialize record-level array for tracking min/max 853/4/5 vals
  # 99999 (min) and 0 (max) will be replaced by real data
  my @f85x_vals = (99999, 0, 99999, 0, 99999, 0);

  # Get OCLC number for this record
  $fld = $record->field('001');
  my $mfhd_id = $fld->data();
  my $oclc = $data{$mfhd_id};

  # Set LDR/17 based on existence of 853/863 and 866
  my $leader = $record->leader();
  my $has_866 = $record->field('866');
  my $has_8x3 = ($record->field('853') || $record->field('863'));
  substr($leader, 17, 1, '3') if ($has_866 && ! $has_8x3);
  substr($leader, 17, 1, '4') if (! $has_866 && $has_8x3);
  substr($leader, 17, 1, '5') if ($has_866 && $has_8x3);
  $record->leader($leader);

  # Create default 007 for text, if none exists
  $fld = $record->field('007');
  if (! $fld) {
    $record->insert_fields_ordered(MARC::Field->new('007', 'tu'));
  }
  # Otherwise, if 007 contains just 't', update it
  elsif ($fld->data() eq 't') {
    $fld->update('tu');
  }

  # Use location code to determine lending/reproduction policy
  $fld = $record->field('852');
  my $loc = $fld->subfield('b');
  my $policy = get_policy($loc);

  # Validate 008 field, replace it if bad
  $fld = $record->field('008');
  my $f008 = get_valid_008_data($fld);

  # Set 008/20-21 policy
  substr($f008, 20, 2) = $policy;
  $fld->update($f008);
    
  # Remove 004, 014, 035 and 9xx fields
  my @del_tags = qw(004 014 035 9..);
  for my $del_tag (@del_tags) {
    @flds = $record->field($del_tag);
    $record->delete_fields(@flds);
  }

  # Add a new OCLC 035 field
  my $oclc_035 = MARC::Field->new('035', '', '', a=>'(OCoLC)'.$oclc);
  $record->insert_fields_ordered($oclc_035);

  # Remove all $x staff notes from 852 and 86x fields
  $fld = $record->field('852');
  $fld->delete_subfield(code => 'x');
  @flds = $record->field('86.');
  foreach $fld (@flds) {
    $fld->delete_subfield(code => 'x');
  }

  # Add 852 $a ZASSP
  $fld = $record->field('852');
  $fld->add_subfields('a' => 'ZASSP');

  # Remove 853/4/5 if record lacks 863/4/5 (863 for 853, etc.)
  @flds = $record->field('85[345]');
  foreach $fld (@flds) {
    my $tag86x = $fld->tag;
    substr($tag86x, 1, 1, '6');
    my $has_86x = $record->field($tag86x);
    $record->delete_fields($fld) if (! $has_86x);
  }

  # Collect linking numbers from current 853/4/5 fields
  my @f85x = $record->field('85[345]');
  foreach $fld (@f85x) {
    $link_val = $fld->subfield('8');
    $tag = $fld->tag;
    @f85x_vals = set_min_max_f85x($tag, $link_val, @f85x_vals);
  } # foreach @f85x

  # Add $8 to each 866/7/8 currently lacking $8
  # $8 must be first subfield in field
  my @f86x = $record->field('86[678]');
  foreach $fld (@f86x) {
    $tag = $fld->tag;
    # Map 86x tag to 85x
    my $linked_tag;
    $linked_tag = '853' if $tag eq '866';
    $linked_tag = '854' if $tag eq '867';
    $linked_tag = '855' if $tag eq '868';

    # Make decisions based on existence of $linked_tag
    my $has_linked_tag = $record->field($linked_tag);

    # Add $8 to fields without one
    if ($has_linked_tag) {
      # Add $8 with increasing value
      my $newfld = get_field_with_sfd8($fld, $new_val);
      $fld->replace_with($newfld);
      $new_val++;
    } else {
      # Add $8 with 0
      my $newfld = get_field_with_sfd8($fld, 0);
      $fld->replace_with($newfld);
    }

    # Replace any $8 0 with real linking numbers greater than tag-relevant max value
    if ($has_linked_tag) {
      my $sfd8 = $fld->subfield('8');
      if ($sfd8 eq '0') {
        $new_val = get_max_f85x($linked_tag, @f85x_vals) + 1;
        @f85x_vals = set_min_max_f85x($linked_tag, $new_val, @f85x_vals);
        $fld->update('8', $new_val);
      }
    }

  } # foreach f86x

  # Write the new LHR to file
  print OUT $record->as_usmarc();
}

close OUT;
close DATA;
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

sub get_valid_008_data {
  my $fld = shift;
  my $yymmdd = get_yymmdd();
  my $default = $yymmdd.'0u    8   0001uu   0'.$yymmdd;
  my $f008;
  # If no 008 or wrong length, use generic default 008
  if ($fld) {
    $f008 = $fld->data();
    $f008 = $default if (length($f008) != 32);
  } else {
    $f008 = $default;
  }
  return $f008;
}

sub get_policy {
  my $loc = shift;
  my $policy = "uu"; # default
  for ($loc) {
    if    (/^sr$/)    {$policy = "uu";}
    elsif (/^srucl$/) {$policy = "uu";} #different from ZAS
    elsif (/^srucl2/) {$policy = "bb";}
    elsif (/^srucl3/) {$policy = "uu";} #different from ZAS
    elsif (/^srucl4/) {$policy = "uu";}
  }
  return $policy;
}

sub max {
  my ($x, $y) = @_;
  return ($x >= $y ? $x : $y);
}

sub min {
  my ($x, $y) = @_;
  return ($x <= $y ? $x : $y);
}

# Update @85x_vals array by setting appropriate min/max for tag from val
sub set_min_max_f85x {
  my ($tag, $val, @arr) = @_;
  if ($tag eq '853') {
    $arr[0] = min($val, $arr[0]);
    $arr[1] = max($val, $arr[1]);
  } elsif ($tag eq '854') {
    $arr[2] = min($val, $arr[2]);
    $arr[3] = max($val, $arr[3]);
  } elsif ($tag eq '855') {
    $arr[4] = min($val, $arr[4]);
    $arr[5] = max($val, $arr[5]);
  }
  return @arr;
}

# Retrieve max val for given tag
sub get_max_f85x {
  my ($tag, @arr) = @_;
  my $val = 1;
  if ($tag eq '853') {
    $val = $arr[1];
  } elsif ($tag eq '854') {
    $val = $arr[3];
  } elsif ($tag eq '855') {
    $val = $arr[5];
  }
  return ($val == 0 ? 1 : $val);
}

# Retrieve min val for given tag
sub get_min_f85x {
  my ($tag, @arr) = @_;
  my $val = 1;
  if ($tag eq '853') {
    $val = $arr[0];
  } elsif ($tag eq '854') {
    $val = $arr[2];
  } elsif ($tag eq '855') {
    $val = $arr[4];
  }
  return ($val == 99999 ? 1 : $val);
}

# Add subfield 8 with $new_val to $fld
# Returns $fld unchanged if subfield 8 already present
sub get_field_with_sfd8 {
  my ($fld, $new_val) = @_;
  my $newfld;
  my $sfd8 = $fld->subfield('8');
  if (! defined $sfd8) {
    my @newsfds = ();
    # Start with $8
    push(@newsfds, '8', $new_val);
    # Must copy each existing subfield (deref to code/val); can't just push(@newsfds, $fld->subfields())
    foreach my $sfd ($fld->subfields()) {
      push(@newsfds, $sfd->[0], $sfd->[1]);
    }
    $newfld = MARC::Field->new(
      $fld->tag, $fld->indicator(1), $fld->indicator(2), @newsfds
    );
  } # added $sfd8
  else {
    $newfld = $fld;
  }
  return $newfld;
}
