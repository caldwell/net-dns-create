#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package Net::DNS::Create::Bind;
use Net::DNS::Create qw(internal full_host email interval);
use feature ':5.10';
use strict;
use warnings;

use POSIX qw(strftime);
use File::Slurp qw(write_file);

our %config = (conf_prefix=>'', default_ttl=>'1h');
sub import {
    my $package = shift;
    my %c = @_;
    $config{$_} = $c{$_} for keys %c;
}

sub txt($) {
    my ($t) = @_;
    return "\"$t\"" if length $t < 255;
    my @part;
    push @part, $1 while ($t =~ s/^(.{255})//);
    '('.join("\n" . " " x 41, map { "\"$_\"" } @part, $t).')';
}

our @zone;
sub domain {
    my ($package, $domain, $entries) = @_;

    my $conf = '$TTL  '.interval($config{default_ttl})."\n".
               join '', map { my $node = $_;
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

                                  $rr eq 'txt' && ref $val eq 'ARRAY' ? map {
                                                       "$prefix ".txt($_)."\n"
                                                    } @$val :

                                  $rr eq 'srv'   ? map {
                                                         my $target = $_;
                                                         map {
                                                               "$prefix ".($_->{priority} // "0")
                                                                     ." ".($_->{weight} // "0")
                                                                     ." ".($_->{port})
                                                                     ." ".$target."\n"
                                                             } (ref $val->{$_} eq 'ARRAY' ? @{$val->{$_}} : $val->{$_})
                                                       } keys %$val :
                                  sprintf("%s %s\n", $prefix,
                                          $rr eq 'txt' ? txt($val) :
                                          $rr eq 'rp' ? email($val->[0]).' '.$val->[1] :
                                          $rr eq 'soa' ? join(' ', full_host($val->{primary_ns}),
                                                                   email $val->{rp_email}, '(', strftime('%g%m%d%H%M', localtime),
                                                                                                (map { interval $_ } $val->{refresh}, $val->{retry}, $val->{expire}, $val->{min_ttl}),
                                                                                           ')') :
                                          $val);

                              } keys %{$entries->{$node}}
    } keys %$entries;

    my $conf_name = "$config{conf_prefix}$domain.zone";
    push @zone, { conf => $conf_name, domain => $domain };
    write_file($conf_name, $conf);
}

sub master {
    my ($package, $filename, $prefix, @extra) = @_;
    $prefix //= '';
    write_file($config{conf_prefix}.$filename,
               @extra,
               map { <<EOZ
zone "$_->{domain}" {
    type master;
    file "$prefix$_->{conf}";
};

EOZ
               } @zone);
    system("named-checkconf", "-z", $config{conf_prefix}.$filename);
}

sub domain_list($@) {
    print "$config{conf_prefix}$_[0].zone\n";
}

sub master_list($$) {
    print "$config{conf_prefix}$_[0]\n"
}

1;
