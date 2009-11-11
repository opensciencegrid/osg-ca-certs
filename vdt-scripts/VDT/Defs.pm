package VDT::Defs;

use strict;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&read_defs);

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
        next unless($key && defined($value));
        $value =~ s/\$\(([^\)]+)\)/$tmp{$1}/g;
        $tmp{$key} = $value;
    }
    return \%tmp;
}

1;
