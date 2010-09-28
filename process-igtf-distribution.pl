#!/usr/bin/perl -w

use strict;
use warnings;

use File::Basename;
use File::Find;
use POSIX qw(strftime);

# ========== BEGIN CONFIGURABLE ITEMS ==========

# Output filename templates (@VERSION@ comes from IGTF directory name)
my $UPDATE_SCRIPT_FILENAME_TEMPLATE = 'igtf-@VERSION@-update-script.sh';
my $UPDATE_DIFF_FILENAME_TEMPLATE = 'igtf-@VERSION@-update-diffs.log';

# CA Certificate hashes that are known to NOT be in the IGTF distro but are
# going to be part of the VDT.
my @WHITELIST = (
     # Moved TeraGrid CAs from whitelist to blacklist when we stopped including them (Sept 2008)
    '290a3b29',   # PSC Kerberos CA (TeraGrid)
    '34a5e0db',   # Telescience (TeraGrid)
    '3deda549',   # SDSC (TeraGrid)
    '4a6cd8b1',   # National Center for Supercomputing Applications (TeraGrid)
    '67e8acfa',   # Purdue TeraGrid RA
    '95009ddc',   # Purdue CA
    '9a1da9f9',   # TACC (TeraGrid)
    '9b88e95b',   # PSC Root CA (TeraGrid)
    'acc06fda',   # PSC Hosts CA (TeraGrid)
    'b89793e4',   # NPACI / SDSC (TeraGrid)
    'bc82f877',   # NASA / Ames Research Center
);

# CA Certificate hashes that we never want to add to the VDT.
my @BLACKLIST = (
    '225860ae',   # EDG tutorial worthless CA
    '75304a28',   # Dutch demo worthless CA
    '84c1f123',   # Old, expired CyGridCA certificate
    '85ca9edc',   # PSC Kerberos (TeraGrid) - EXPIRED 2006-08-20
    'aa99c057',   # PSC (TeraGrid) - EXPIRED 2006-08-20
    'b38b4d8c',   # Globus worthless CA
);

# ========== END CONFIGURABLE ITEMS ==========

if ($#ARGV != 1) {
    die "Usage: $0 igtf-directory svn-checkout\n";
}

my %HASH_WHITELIST = map { $_ => 1 } @WHITELIST;
my %HASH_BLACKLIST = map { $_ => 1 } @BLACKLIST;

my $certificate_directory = shift;
my $vdt_directory = shift;

$certificate_directory =~ m|([\d.]*)$|;
die "Could not extract IGTF version from directory name\n" unless $1;
my $igtf_version = $1;
(my $update_script_filename = $UPDATE_SCRIPT_FILENAME_TEMPLATE) =~ s|\@VERSION\@|$igtf_version|;
(my $update_diff_filename = $UPDATE_DIFF_FILENAME_TEMPLATE) =~ s|\@VERSION\@|$igtf_version|;

open(SCRIPT, "> $update_script_filename") or die "Could not write to $update_script_filename: $!\n";
open(DIFFS, "> $update_diff_filename") or die "Could not write to $update_diff_filename: $!\n";

chmod(0755, "$update_script_filename");

# Begin stdout, SCRIPT, and DIFFS
my $timestamp = strftime('%Y-%m-%d %H:%M:%S', localtime);
print "Checking CA certificates for updates:\n";
print "    IGTF directory: $certificate_directory\n";
print "    VDT to update:  $vdt_directory\n\n";

print SCRIPT "#!/bin/sh

# Do not run this shell script until you have verified the correctness
# of each command by hand.

# Created by $0 at $timestamp

IGTF=$certificate_directory
VDT_CERTS=$vdt_directory/certificates
\n";

print DIFFS "This file displays the differences between changed CA certificate files.
Generated:       $timestamp
IGTF directory:  $certificate_directory
VDT directory:   $vdt_directory\n";

# Get all unique certificate hashes
my %certificate_hash;
collect_certificate_hashes($certificate_directory, $vdt_directory);

# Process each certificate hash
print "Updates to CA certificates, by hash:\n";
foreach my $hash (sort(keys(%certificate_hash)))
{
    my $igtf_name = get_igtf_name_for_hash($hash);
    printf("    $hash %-25s ... ", ($igtf_name ? $igtf_name : '---'));
    my $differences = 0;
    my $new_files = 0;
    my $old_files = 0;
    my $blacklisted_files = 0;
    my @notices;

    # Iterate through list of IGTF files that start with the hash
    if (not defined $HASH_BLACKLIST{$hash})
    {
        foreach my $igtf_path (glob("$certificate_directory/$hash.*"))
        {
            my $igtf_basename = basename($igtf_path);
            my $vdt_cert_path = "$vdt_directory/certificates/$igtf_basename";

            # Skip files we don't care about
            # No longer needed for IGTF?
            # next if ($igtf_basename =~ m/\.(alias|requires)$/i);

            # Make sure this file is a plain file
            if (not -f $igtf_path)
            {
                push(@notices, "$igtf_basename is not a plain file");
            }

            # Check for file's existence in the VDT
            elsif (not (-e $vdt_cert_path and -f $vdt_cert_path))
            {
                $new_files++;
                print SCRIPT "cp \$IGTF/$igtf_basename \$VDT_CERTS/$igtf_basename\n";
                print SCRIPT "svn add \$VDT_CERTS/$igtf_basename\n";
            }

            # Check for readability
            elsif (not -r $igtf_path)
            {
                push(@notices, "$igtf_path not readable");
            }
            elsif (not -r $vdt_cert_path)
            {
                push(@notices, "$vdt_cert_path not readable");
            }

            # Check for differences
            elsif (system("cmp -s $igtf_path $vdt_cert_path"))
            {
                $differences++;
                print DIFFS "\n##### Comparing different versions of $igtf_basename\n";
                print DIFFS `diff -u $vdt_cert_path $igtf_path`;
                print SCRIPT "cp \$IGTF/$igtf_basename \$VDT_CERTS/$igtf_basename\n";
            }
        }
    }

    # Iterate through list of VDT files that start with the hash
    if (not defined $HASH_WHITELIST{$hash})
    {
	foreach my $vdt_path (glob("$vdt_directory/certificates/$hash.*"))
	{
	    my $vdt_basename = basename($vdt_path);

	    # Check for existence in IGTF
	    my $igtf_path = `find $certificate_directory -name $vdt_basename`;
	    chomp($igtf_path);
	    if (not $igtf_path)
	    {
 		$old_files++;
		print SCRIPT "svn delete \$VDT_CERTS/$vdt_basename\n";
	    }
	}
    }

    # Make sure blacklisted items are removed
    if (defined $HASH_BLACKLIST{$hash})
    {
	foreach my $vdt_path (glob("$vdt_directory/certificates/$hash.*"))
	{
	    my $vdt_basename = basename($vdt_path);
            $blacklisted_files++;
            print SCRIPT "svn remove \$VDT_CERTS/$vdt_basename\n";
        }        
    }

    my @status;
    push(@status, "$new_files file" . ($new_files != 1 and 's') . " added") if $new_files;
    push(@status, "$differences file" . ($differences != 1 and 's') . " changed") if $differences;
    push(@status, "$old_files file" . ($old_files != 1 and 's') . " not in IGTF") if $old_files;
    if (defined $HASH_BLACKLIST{$hash})
    {
        push(@status, "blacklisted in the VDT");
        push(@status, "$blacklisted_files file" . ($blacklisted_files != 1 and 's') . " removed") if $blacklisted_files;
    }
    print((@status ? join(', ', @status) : "<no change>"), "\n");
    print join("\n", @notices), "\n" if @notices;
}

sub collect_certificate_hashes
{
    find(\&process_found_file, @_);
}

sub process_found_file
{
    return ($File::Find::prune = 1) if -d and $_ eq '.svn';   # Skip SVN directories
    $certificate_hash{$1} = 1 if m/^([0-9a-f]{8})\./i;
}

sub get_igtf_name_for_hash
{
    my $hash = shift;
    my $alias_line = `grep alias $certificate_directory/$hash.info 2>/dev/null`;
    $alias_line =~ m|alias\s*=\s*(.*)$|;
    return $1;
}
