#!/usr/bin/perl

use Date::Parse;

$grace=60*60*24*14;

foreach $FILE (@ARGV) {
  $out = `openssl x509 -enddate -noout < $FILE`;
  chomp($out);
  $out =~ /notAfter=(.*)/;
  $notafter = $1;
  $time = str2time($notafter);
  $timeleft = $time-$^T;
  if ($timeleft < 0) {
    print "$FILE has expired!\n";
  } elsif ($timeleft < $grace) {
    printf "%s will expire in %.1f days.\n", $FILE, $timeleft/60.0/60.0/24.0;
  }
}
