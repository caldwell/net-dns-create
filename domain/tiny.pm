#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package domain::tiny;
use feature ':5.10';
use strict;
use warnings;

use domain qw(internal full_host email interval);
use File::Slurp qw(write_file);

our %config = (default_ttl=>'1h');
sub import {
    my $package = shift;
    my %c = @_;
    $config{$_} = $c{$_} for keys %c;
}

sub tiny_escape($) {
    my ($f) = @_;
    $f =~ s/(:|\\|[^[:print:]])/sprintf "\\%03o", ord($1)/eg;
    $f
}

sub domainname_encode($;$) {
    my ($node, $domain) = @_;
    $node = full_host($node, $domain);
    join('', map { chr(length $_).$_ } split /\./, $node, -1);
}

my @domain;
sub domain($$) {
    my ($package, $domain, $entries) = @_;

    my $ttl = interval($config{default_ttl});
    my @conf = map { my $node = $_;
                     my $fqdn = "$_.$domain.";
                     $fqdn =~ s/^@\.//;
                     map {
                         my $rr = lc $_;
                         my $val = $entries->{$node}->{$_};

                         $rr eq 'a'     ? "=$fqdn:$val:$ttl" :
                         $rr eq 'cname' ? "C$fqdn:$val:$ttl" :
                         $rr eq 'rp'    ? ":$fqdn:17:".tiny_escape(domainname_encode(email($val->[0])).domainname_encode($val->[1], $domain)).":$ttl" :
                         $rr eq 'mx'    ? map {
                                                  "\@$fqdn:\:$val->{$_}.$fqdn:$_:\:$ttl"
                                              } keys %$val :
                         $rr eq 'ns'    ? map {
                                                  "&$fqdn:\:$_:\:$ttl"
                                              } @$val :
                         $rr eq 'txt'   ? ref $val eq 'ARRAY' ? map {
                                                                        "'$fqdn:".tiny_escape($_).":$ttl"
                                                                    } @$val
                                                              : "'$fqdn:".tiny_escape($val).":$ttl" :
                         $rr eq 'soa'   ? join(':',
                                               "Z$fqdn",
                                               full_host($val->{primary_ns}, $domain),
                                               email($val->{rp_email}),
                                               $val->{serial} || '',
                                               (map { interval $_ } $val->{refresh}, $val->{retry}, $val->{expire}, $val->{min_ttl}),
                                               $ttl) :
                         $rr eq 'srv'   ? map {
                                                my $target = $_;
                                                map {
                                                      ":$fqdn:33:".tiny_escape(pack("nnn",
                                                                                    $_->{priority} // 0,
                                                                                    $_->{weight} // 0,
                                                                                    $_->{port})
                                                                               .domainname_encode($target, $domain)).":$ttl";
                                                    } (ref $val->{$_} eq 'ARRAY' ? @{$val->{$_}} : $val->{$_})
                                              } keys %$val :
                            die "Don't know how to handle \"$rr\" RRs yet.";

                     } keys %{$entries->{$node}}
                   } keys %$entries;

    push @domain, "# $domain\n" .
                  "#\n" .
                  join('', map { "$_\n" } @conf) .
                  "\n";
}

sub master {
    my ($package, $filename, $prefix, @extra) = @_;
    $prefix //= '';
    write_file($filename, @domain);
}

sub domain_list($@) {
    # There are no separate zone files in a tiny setup.
}

sub master_list($$) {
    print "$_[0]\n"
}

1;
