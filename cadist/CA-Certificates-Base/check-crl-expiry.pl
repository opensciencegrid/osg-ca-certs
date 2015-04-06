#!/usr/bin/perl

use Date::Parse;

$dontwarn = "67e8acfa|95009ddc|d1737728";

$grace=60*60*24*3-10;

foreach $FILE (@ARGV) {
  $out = `openssl crl -nextupdate -noout < $FILE`;
  chomp($out);
  $out =~ /nextUpdate=(.*)/;
  $nextupdate = $1;
  $out = `openssl crl -lastupdate -noout < $FILE`;
  chomp($out);
  $out =~ /lastUpdate=(.*)/;
  $lastupdate = $1;
  $nextupdatetime = str2time($nextupdate);
  $lastupdatetime = str2time($lastupdate);
  $timeleft = $nextupdatetime-$^T;
  if ($timeleft < 0) {
    print "$FILE has expired!\n";
  } elsif ($timeleft < $grace && !($FILE =~ $dontwarn)) {
      printf "%s will expire in %.1f", $FILE, $timeleft/60.0/60.0/24.0;
      printf " days (out of %.1f).\n",
             ($nextupdatetime-$lastupdatetime)/60.0/60.0/24.0;
  }
}
