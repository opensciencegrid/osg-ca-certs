#!/usr/bin/perl -w
#
# build the index files (.txt, .html) for the certificates directory contents
# from the CA.info files
#
#  INDEX.txt file is used by RSV probes to monitor CA certificates and
#  CRLs.
#  All lines not identifying an installed CA should begin with #.
#  Lines identifying installed CAs are whitespace delimited columns
#  with the first column being CA hash value (openssl 0.x) and
#  the last column identifying which CAs are accredited by IGTF.
#     I = IGTF accredited
#     N = not IGTF accredited
#  Column 2 is CA hash value for openssl 1.x.  We hope this can be used
#  by future RSV probes to deal with installations that may have either
#  openssl 0.x or 1.x.
#  Other columns are ignored for RSV probe uses.
#  INDEX.txt has a typed format begining with type 1 on 7 June 2010.
#    unversioned type before 7 June 2010
#    IndexTypeVersion = 1  created 7 June 2010
#
#  INDEX.html is used to display the current CA package on the OSG web site
#  (twiki).
#

use strict;
use warnings;

use File::Basename;
use File::Find;
use Getopt::Long;

my @keys = qw(dir out debug version ssl1 style format);
my %args;
@args{@keys} = ("") x @keys;
GetOptions(\%args,"out=s","dir=s","help+","debug+","version=s","ssl1=s","format=s","style=s");

my $castyle = "new";  # type of IGTF release layout
my $IndexTypeVersion = 1; # INDEX.txt format number
my $ssl1bin = "/usr/local/ssl/bin/openssl";

if ( $args{help} ) {
  usage();
  exit;
}
if ( defined $args{style} ) {
  $castyle = $args{style};
}

if ( defined $args{format} ) {
  $IndexTypeVersion = $args{format};
}
if ( $IndexTypeVersion < 0 || $IndexTypeVersion > 1 ) {
  print "bad format number, $IndexTypeVersion\n";
  usage();
  exit 1;
}
if ( $args{ssl1} ) {
  $ssl1bin = $args{ssl1};
}
my @sslcheck = split(' ',`$ssl1bin version`);
if ( index($sslcheck[1],'1') != 0 ) { print "missing openssl 1.x\n"; usage(); exit; }

######################################################################
###### declare functions ############################################
################## read in parameters ##################
##  recipe taken from http://www.unix.com.ua/orelly/perl/cookbook/ch08_17.htm
#
#  $infile = pathname of file to read (name = value format)
#  $pref = reference to input hash
#  $behavior = flag to indicate behavior for names listed in file
#            = a - means add names in file to keys in $$pref hash
#            = !a - means don't add name as new key, and print warning
#
sub read_params($$$$) {
  my $infile = shift;
  my $pref = shift;
  my $behavior = shift;
  my $debug = shift;
  if ( ! $behavior ) { $behavior = "n"; }
  my $cnt=0;
  if ( $debug  ) { print "read_params: try reading ", $infile, "\n"; }
  open(PARAMS," < $infile") || return;
  while (<PARAMS>) {
    chomp;                  # no newline
    s/#.*//;                # no comments
    s/^\s+//;               # no leading white
    s/\s+$//;               # no trailing white
    next unless length;     # anything left?
    if ( index($_,"=") > 0 ) {
      my ($var, $value) = split(/\s*=\s*/, $_, 2);
      if ( exists $$pref{$var}  ||  "a" =~ /$behavior/ ) {
        $$pref{$var} = $value;
        if ( $debug ) { print " var=value: ",$var," = ",$value,"\n";}
      } else {
        print " read_params warning: undefined ",$var," = ",$value,"\n";
      }
      $cnt++;
    }
  }
  close( PARAMS );
  print "read ", $cnt, " parameters from ", $infile, "\n";
  return $cnt;
}

sub usage {
  print "$0: --version <version> [--dir <input directory>] 
             [--out <index file>] [-- ssl1 <path to openssl 1.x>] [--help]
             [--format <type>] [--style <style>]
   Generates a index files (INDEX.html, INDEX.txt) of CA certificates from 
   the parameters contained in the .info files for the CAs.
   <version> = OSG version number for this CA package release
   <input directory> = directory containing CA files, default is . (CWD)
   <index file> = output file (including path) of generated index file,
                 default is INDEX (making INDEX.html, INDEX.txt)
   <path to openssl 1.x> = location of openssl command with version 1.x supporting
         -subject_hash_old, defaults to /usr/local/ssl/bin/openssl
   <type> = format type number of output, 0 = original, 1 = June 2010, other=error
              0 = before changes for openssl 1.x new & old hash values
              1 = had openssl 1.x new and old hash values
   <style> = layout style, defaults to new meaning symlinks to hash files,
             old style means only files named with hash value and no symlinks
             or alias names.

"};

########################################################################
########################################################################
##### continue with main ###############################################
my ($cabasename,$certpath,$cext);
my %cas; # list of CAs
my $ncas=0;

if ( ! $args{dir} ) { $args{dir} = "."; }
if ( ! $args{out} ) { $args{out} = "INDEX" }
if ( ! $args{version} ) { usage(); exit 1; }

print "Generating $args{out} for CA files in $args{dir} for version $args{version} in style $args{style}\n";

while ( my $infofile = glob("$args{dir}/*.info") ) {
  if ( $args{debug} ) {  print "$infofile\n"; }
  # skip symlinks and the policy-igtf-profile.info files
  if ( ! -l $infofile and (index($infofile,"policy-igtf")<0)) {
    my %cainfo;
    my $np = read_params($infofile,\%cainfo,"a",$args{debug});
    if ( $args{debug} ) {
      print "Read $np parameters\n";
    }
    if ( $castyle eq "old" ) {
# klug for old format #####################################################
#  use CA filename hash value as key to %cas
      ($cabasename,$certpath,$cext) = fileparse($infofile,qr/\.[^.]*/);
      print " basename: $cabasename \n";
##########################################################################
    }
    $ncas++;
    my @ikeys = keys %cainfo;
    while ( my $cakey = shift(@ikeys) ) {
      if ( $args{debug} ) {
	print "      $cakey = " . $cainfo{$cakey} . "\n";
      }
      if ( $castyle eq "old" ) {
	$cas{$cabasename}{$cakey} = $cainfo{$cakey};
      } else {
	$cas{$cainfo{alias}}{$cakey} = $cainfo{$cakey};
      }
    }
  } else {
    if ( $args{debug} ) {
      print "skipping symlink $infofile\n";
    }
  }
}

my $title = "Contents of Certificate Package (version $args{version}) distributed by OSG Security team via the OSG GOC";
my $header = "Contents of current OSG CACert Distribution (version $args{version})";
open(OH,">","$args{out}.html") or die "Failed to open $args{out}.html for write";
open(OT,">","$args{out}.txt") or die "Failed to open $args{out}.txt for write";

######### html #################
print OH "<html>\n";
print OH "<head><title>$title</title></head>\n";
print OH "<body>\n";
print OH "<h2>$header</h2>\n";
print OH "<p> This page provides a table of all $ncas CAs that are part of\n";
print OH " version $args{version} of the OSG CACert distribution - as \n";
print OH "provided by the OSG security team.\n";
print OH "<p> If you are curious about what has changed in each \n";
print OH "CA certificate release, then check the \n";
print OH "<a href='CHANGES'>CA certificate change log</a>. \n";
print OH "The ca-certs-version file used by pacman is \n";
print OH "<a href='ca-certs-version'>here</a>. \n";
#[12/27/17]print OH "A list of md5sums is available in \n";
#[12/27/17]print OH "<a href='cacerts_md5sum.txt'>cacerts_md5sum.txt file</a>.\n";
#[01/12/18]Uncommenting the above comments
print OH "A list of md5sums is available in \n";
print OH "<a href='cacerts_md5sum.txt'>cacerts_md5sum.txt file</a>.\n";

print OH "A list of sha256sums is available in \n";
print OH "<a href='cacerts_sha256sum.txt'>cacerts_sha256sum.txt file</a>.\n";
print OH "<table border='1' cellspacing='2' cellpadding='2'><tr>";
if ( $castyle eq "new" ) {
#Commenting this line [07/03/2017]  print OH "<td><b>OldHash</b></td>";
  print OH "<td><b>NewHash</b></td>";
} else {
  print OH "<td><b>Hash</b></td>";
  print OH "<td><b>CA Alias</b></td>";
}
print OH "<td><b>CAfile</b></td>";
print OH "<td><b>URL</b></td>";
print OH "<td><b>Version</b>[<a href=\"#note1\">1</a>]</td>";
print OH "<td><b>Accreditation Status</b></td>";
print OH "</tr>\n";

######### txt #################
if ( $IndexTypeVersion == 0 ) {
printf OT ("# %-12s %-24s %-40s %5s\n","Hash","Source","URL","Accreditation");
} else {
  if ( $castyle eq "new" ) {
    printf OT ("# %-12s %-12s %-24s %-40s %10s   %-16s\n","OldHash","NewHash","CAfile","CAURL","Version","Accreditation");
  } else {
    printf OT ("# %-12s %-12s %-24s %-40s %10s   %-16s\n","Hash","CA Alias","CAfile","CAURL","Version","Accreditation");
  }
}
print OT "#--------------------------------------------------------------------------------------------------------\n";

my ($oldhash,$newhash,$capem,$cafile);
my @cakeys = sort {lc $a cmp lc $b} keys %cas;
if ( $args{debug} ) { print "cakeys @cakeys\n"; }
while ( my $ca = shift(@cakeys) ) {
  my $caname = $ca;
  if ( $castyle eq "new" ) {
    $cafile = "$caname.pem";
  } elsif ( $castyle eq "old" ) {
    $cafile = "$caname.0";
  } else {
    print "Error with style = $castyle\n";
  }
  $capem = "$args{dir}/$cafile";
  $newhash = `$ssl1bin x509 -in $capem -noout -subject_hash`; chomp($newhash);
  $oldhash = `$ssl1bin x509 -in $capem -noout -subject_hash_old`; chomp($oldhash);
  my $caurl = $cas{$ca}{url};
  if ( ! defined($caurl)) {
    $caurl = $cas{$ca}{ca_url};
  }
  my $version = $cas{$ca}{version};
  my $status = $cas{$ca}{status};
  my $caalias = $cas{$ca}{alias};
  if ( $args{debug} ) {
    print "CA $oldhash, $newhash, $cafile, $caurl, $version, $status\n";
  }
  ########### html ##################
  print OH "<tr>";
  print OH "<td>$oldhash</td";
  if ( $castyle eq "new" ) {
    print OH "<td>$newhash</td>";
  } else {
    print OH "<td>$caalias</td>";
  }
  print OH "<td>$cafile</td>";
  print OH "<td>$caurl</td>";
  print OH "<td>$version</td>";
  print OH "<td>$status</td>";
  print OH "</tr>\n";
  ########### txt ##################
  my $ts;
  if ( index($status,"accredited") == 0 ) {
    $ts = "I";
  } else {
    $ts = "N";
  }  
  if ( $IndexTypeVersion == 0 ) {
    printf OT ("%-12s %-24s %-40s %3s\n",$oldhash,$caalias,$caurl,$ts);
  } else {
    if ( $castyle eq "new" ) {
      printf OT ("%-12s %-12s %-24s %-40s %10s %3s\n",$oldhash,$newhash,$cafile,$caurl,$version,$ts);
    } else {
      printf OT ("%-12s %-12s %-24s %-40s %10s %3s\n",$oldhash,$caalias,$cafile,$caurl,$version,$ts);
    }
  }
#  print OT "$ca\t";
#  print OT "$caurl\t";
#  print OT "$version\t";

}
############ html ##################
print OH "</table>\n";
print OH "<hr><b>Notes</b><br><a name=\"note1\">";
print OH "<b>1</b> Version number is the IGTF release number except for CAs not included in IGTF, and then it is the OSG release number.<br/>\n";
#Commenting this line [07/03/2017] print OH "<b>OldHash</b> is the CA subject hash for openssl 0.9x<br/>\n";
print OH "<b>NewHash</b> is the CA subject has for openssl 1.x<br/>\n";
print OH "</body></html>\n";
close(OH);
############### txt ###################
print OT "#--------------------------------------------------------------------------------------------------------\n";
print OT "#\n";
print OT "# OSGversion $args{version}\n";
#if ( index($args{version},"ITB")>1 ) {
#  print OT "# Repository http://software-itb.grid.iu.edu/cadist/\n";
#} else {
#  print OT "# Repository http://software.grid.iu.edu/cadist/\n";
#}
print OT "# IndexTypeVersion $IndexTypeVersion\n";
print "Index of $ncas CAs\n";
exit;

