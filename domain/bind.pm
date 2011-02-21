#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package domain::bind;

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
    $_[0] =~ /(\d+)([hmsdw])/ && $1 * { s=>1, m=>60, h=>3600, d=>3600*24, w=>3600*24*7 }->{$2} || $_[0];
}

sub txt($) {
    my ($t) = @_;
    return "\"$t\"" if length $t < 255;
    my @part;
    push @part, $1 while ($t =~ s/^(.{255})//);
    '('.join("\n" . " " x 41, map { "\"$_\"" } @part, $t).')';
}

our @zone;
our $conf_prefix='';
our $default_ttl='1h';
sub _domain($$) {
    my ($domain, $entries) = @_;

    my $conf = '$TTL  '.interval($default_ttl)."\n".
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
                                          $rr eq 'soa' ? join(' ', full_host $val->{primary_ns},
                                                                   email $val->{rp_email}, '(', strftime('%g%m%d%H%M', localtime),
                                                                                                (map { interval $_ } $val->{refresh}, $val->{retry}, $val->{expire}, $val->{min_ttl}),
                                                                                           ')') :
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

sub master {
    my ($filename, $prefix, @extra) = @_;
    $prefix //= '';
    write_file($conf_prefix.$filename,
               @extra,
               map { <<EOZ
zone "$_->{domain}" {
    type master;
    file "$prefix$_->{conf}";
};

EOZ
               } @zone);
    system("named-checkconf", "-z", $conf_prefix.$filename);
}

sub soa(%) {
    my %param = @_;
    return (soa => \%param);
}

sub list() {
    no warnings;
    *domain = *main::domain = \&domain_list;
    *master = *main::master = \&master_list;
}

sub domain_list($@) {
    print "$conf_prefix$_[0].zone\n";
}

sub master_list($$) {
    print "$conf_prefix$_[0]\n"
}

1;
