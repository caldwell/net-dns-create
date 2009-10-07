#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package domain;

use feature ':5.10';
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(domain master soa);

use POSIX qw(strftime);
use File::Slurp qw(write_file);

sub full_host($) { $_[0] =~ /\.$/ ? $_[0] : "$_[0]." }

sub email($) {
    my ($email) = @_;
    $email =~ s/@/./g;
    full_host($email);
}

sub interval($) {
    $_ =~ /(\d+)([hmsdw])/ && $1 * { s=>1, m=>60, h=>3600, d=>3600*24, w=>3600*24*7 }->{$2} || $_;
}

sub txt($) {
    my ($t) = @_;
    return "\"$t\"" if length $t < 256;
    my @part;
    push @part, $1 while ($t =~ s/^(.{256})//);
    '('.join("\n" . " " x 41, map { "\"$_\"" } @part, $t).')';
}

our @zone;
our $conf_prefix='';
sub _domain($$) {
    my ($domain, $entries) = @_;

    my $conf = join '', map { my $node = $_;
                              map {
                                  my $rr = lc $_;
                                  my $val = $entries->{$node}->{$_};
                                  my $prefix = sprintf "%-30s in %-5s", $node, $rr;

                                  $rr eq 'mx' ? map {
                                                       "$prefix $_ $val->{$_}\n";
                                                    } keys %$val :

                                  $rr eq 'ns' ? map {
                                                       "$prefix $_\n"
                                                    } @$val :

                                  sprintf("%s %s\n", $prefix,
                                          $rr eq 'txt' ? txt($val) :
                                          $rr eq 'rp' ? email($val->[0]).' '.$val->[1] :
                                          $rr eq 'soa' ? join(' ', full_host $val->[0], email $val->[1], '(', strftime('%g%m%d%H%M', localtime), map { interval $_ } @{$val}[3..$#{$val}], ')') :
                                          $val);

                              } keys %{$entries->{$node}}
    } keys %$entries;

    my $conf_name = "$conf_prefix$domain.zone";
    push @zone, { conf => $conf_name, domain => $domain };
    write_file($conf_name, $conf);
}

use Hash::Merge::Simple qw(merge);
sub domain($@) {
    my ($domain, @entry_hashes) = @_;
    my $entries = {};
    for my $e (@entry_hashes) {
        $entries = merge($entries, $e);
    }
    _domain($domain, $entries);
}

sub master($) {
    my ($filename) = @_;

    write_file($conf_prefix.$filename,
               map { <<EOZ
zone "$_->{domain}" {
    type master;
    file "$_->{conf}";
};

EOZ
               } @zone);
}

sub soa(%) {
    my %param = @_;
    return (soa => [ $param{primary_ns}, $param{rp_email}, $param{serial} // 0, $param{refresh}, $param{retry}, $param{expire}, $param{min_ttl} ]);
}

1;
