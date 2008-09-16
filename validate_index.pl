#!/usr/bin/env perl
use strict;
use warnings;

my (%index, %dir);

# Get hashes in INDEX.txt
open(IN, "certificates/INDEX.txt") or die("Can't open INDEX.txt: $!");
while(<IN>) {
    next unless(/^\s*([0-9a-f]{8})/);
    $index{$1}++;
}
close(IN);

# Get hashes in certificates directory
foreach (`ls -1 certificates/????????.*`) {
    chomp;
    s|certificates/([0-9a-f]{8})\..*|$1|;
    $dir{$_}++;
}

print scalar(keys(%index)) . " hashes found in INDEX.txt\n";
print scalar(keys(%dir))   . " hashes found in certificates directory\n";

my $count = 0;

foreach (keys(%index)) {
    if(!defined($dir{$_})) {
        print "hash $_ found in INDEX, but not in certificates\n";
        $count++;
    }
}

foreach (keys(%dir)) {
    if(!defined($index{$_})) {
        print "hash $_ found in certificates, but not in INDEX\n";
        $count++;
    }
}

if($count == 0) {
    print "\nAll hashes match\n";
}
