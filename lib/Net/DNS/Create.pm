#  Copyright (c) 2011 David Caldwell,  All Rights Reserved. -*- cperl -*-

package Net::DNS::Create;
use strict; use warnings;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(domain master soa);
our @EXPORT_OK = qw(domain master full_host local_host email interval);

my $kind;
our %config = (default_ttl=>'1h');
sub import {
    use Data::Dumper;
    my $package = shift;
    my $import_kind = shift // 'bind';

    # Tricky junk: If the first thing in our import list is "internal" then we just pass the rest to
    # Exporter::export_to_level so that our plugins can include us back and import the full_host, email, and
    # interval utility functions. Otherwise we pass the rest of the import args to the plugin's import so that
    # conf options pass all the way down. In that case we don't pass anything to Exporter::export_to_level so
    # that default export happens.
    if ($import_kind ne 'internal') {
        $kind = __PACKAGE__ . "::" . $import_kind;
        eval "require $kind"; die "$@" if $@;
        $kind->import(@_);
        %config = (%config, @_); # Keep around the config for ourselves so we get the default_ttl setting.
        @_ = ();
    }
    __PACKAGE__->export_to_level(1, $package, @_);
}

sub full_host($;$);
sub full_host($;$) {
    my ($name,$domain) = @_;
    $name eq '@' ? (defined $domain ? full_host($domain) : die "Need a domain with @") :
    $name =~ /\.$/ ? $name : "$name." . (defined $domain ? full_host($domain) : '')
}

sub local_host($$) {
    my ($fq,$domain) = (full_host(shift), full_host(shift));
    return '@' if $fq eq $domain;
    my $local = $fq;
    return $local if substr($local, -length($domain)-1, length($domain)+1, '') eq ".$domain";
    return $fq;
}

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
    return "$t" if length $t < 255;
    my @part;
    push @part, $1 while ($t =~ s/^(.{255})//);
    (@part, $t);
}

use Hash::Merge::Simple qw(merge);
use Net::DNS::RR;
sub domain($@) {
    my ($domain, @entry_hashes) = @_;
    my $entries = {};
    for my $e (@entry_hashes) {
        $entries = merge($entries, $e);
    }

    my $fq_domain = full_host($domain);
    my $ttl = interval($config{default_ttl});
    $entries = [ map { my $node = $_;
                          my $fqdn = full_host($_,$domain);
                          map {
                              my $rr = lc $_;
                              my $val = $entries->{$node}->{$_};
                              my %common = (name => $fqdn,
                                            ttl => $ttl,
                                            type => uc $rr);
                              $rr eq 'a' || $rr eq 'cname' || $rr eq 'rp' || $rr eq 'soa' ?
                                  Net::DNS::RR->new(%common,
                                                    $rr eq 'a'     ? (address       => $val) :
                                                    $rr eq 'cname' ? (cname         => full_host($val, $fq_domain)) :
                                                    #$rr eq 'txt'   ? (char_str_list => [txt($val)]) :
                                                    $rr eq 'rp'    ? (mbox          => email($val->[0]),
                                                                      txtdname      => full_host($val->[1], $fq_domain)) :
                                                    $rr eq 'soa'   ? (mname         => full_host($val->{primary_ns}, $domain),
                                                                      rname         => $val->{rp_email},
                                                                      serial        => $val->{serial} // 0,
                                                                      refresh       => interval($val->{refresh}),
                                                                      retry         => interval($val->{retry}),
                                                                      expire        => interval($val->{expire}),
                                                                      minimum       => interval($val->{min_ttl})) :
                                                    die "can't happen") :

                              $rr eq 'txt' ? map { Net::DNS::RR->new(%common, char_str_list => [txt($_)]) } sort {$a cmp $b} (ref $val eq 'ARRAY' ? @{$val} : $val) :
                              $rr eq 'mx'  ? map { Net::DNS::RR->new(%common, preference => $_, exchange => full_host($val->{$_}, $fq_domain)) } sort(keys %$val) :
                              $rr eq 'ns'  ? map { Net::DNS::RR->new(%common, nsdname => $_) } sort(@$val) :
                              $rr eq 'srv' ? map {
                                                my $target = $_;
                                                map {
                                                    Net::DNS::RR->new(%common,
                                                                      priority => $_->{priority} // 0,
                                                                      weight   => $_->{weight}   // 0,
                                                                      port     => $_->{port},
                                                                      target   => full_host($target))
                                                  } sort {$a cmp $b} (ref $val->{$_} eq 'ARRAY' ? @{$val->{$_}} : $val->{$_})
                                              } sort(keys %$val) :
                                 die uc($rr)." is not supported yet :-("; # Remember to add support for all the backends, too.
                          } keys %{$entries->{$node}};
                      } keys %$entries ];

    $kind->domain($fq_domain, $entries);
}

sub master {
    $kind->master(@_);
}

sub list_files() {
    no warnings;
    *domain = *main::domain = \&{"$kind\::domain_list"};
    *master = *main::master = \&{"$kind\::master_list"};
}

sub list_domains() {
    no warnings;
    *domain = *main::domain = sub { print "$_[0]\n" };
    *master = *main::master = sub {};
}


1;
