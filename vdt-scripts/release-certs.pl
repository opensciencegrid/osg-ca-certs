#!/usr/bin/env perl
use strict;
use warnings;

##
## Parse defs file for version information
##
my %vars = %{read_defs("../defs")};

##
## Global variables
##
my $PACMAN_FILE = "$vars{ROOT}/vdt_cert_cache2/CA-Certificates-Base.pacman";


##
## Make a tarball from the certificates directory
##
print "Certificates version: $vars{OUR_CERTS_MAJOR_VERSION}-$vars{OUR_CERTS_MINOR_VERSION}\n";
if(-e $vars{TARBALL_PATH}) {
    die("ERROR: a tarball already exists at $vars{TARBALL_PATH}\n");
}
system("cd ..; tar czf $vars{TARBALL_PATH} `find certificates ! -name \\*~ ! -name .#\\* ! -type d | grep -v '\.svn'`");
print "Created tarball at $vars{TARBALL_PATH}\n";

##
## Make pacman file
##

# Get template
open(PACMAN, "<", "CA-Certificates-Base.pacman.in") or die("Cannot open CA-Certificates-Base.pacman.in: $!");
my $pacman = join("", <PACMAN>);
close(PACMAN);

# Replace variables
$pacman =~ s/!!([^!]+)!!/$vars{$1}/g;

# Write to cache
open(OUT, ">", "$PACMAN_FILE") or die("Cannot open $PACMAN_FILE for writing: $!");
print OUT $pacman;
close(OUT);


##
## Do other work
##

system("cd ..; ./make-manifest");
system("./make-rpm");
# EDIT - uncomment these two lines when releasing
#system("cp ../certificates/INDEX.txt $vars{ROOT}/releases/certs/ca_index-$(OUR_CERTS_VERSION).txt");
#system("cp ../certificates/CHANGES $vars{ROOT}/releases/certs/ca_changes.txt");


sub read_defs {
    my $file = shift;
    open(DEFS, "<", "$file") or die("Cannot read defs file: $!");
    my @lines = <DEFS>;
    close(DEFS);
    
    # Strip whitespace and comments
    @lines = grep !/^\#/, map { s/^\s+//; s/\s+$//; $_ } @lines;
    
    # Process the lines
    my %tmp;
    foreach my $line (@lines) {
        my ($key, $value) = split /\s*=\s*/, $line, 2;
        next unless($key && $value);
        $value =~ s/\$\(([^\)]+)\)/$tmp{$1}/g;
        $tmp{$key} = $value;
    }
    return \%tmp;
}
