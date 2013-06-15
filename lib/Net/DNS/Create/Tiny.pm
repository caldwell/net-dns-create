#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package Net::DNS::Create::Tiny;
use feature ':5.10';
use strict;
use warnings;

use Net::DNS::Create qw(internal full_host email interval);
use File::Slurp qw(write_file);

our %config = (default_ttl=>'1h');
sub import {
    my $package = shift;
    my %c = @_;
    $config{$_} = $c{$_} for keys %c;
}

sub tiny_escape($) {
    my ($f) = @_;
    $f =~ s/(:|\\|[^ -~])/sprintf "\\%03o", ord($1)/eg;
    $f
}

sub domainname_encode($;$) {
    my ($node, $domain) = @_;
    $node = full_host($node, $domain);
    join('', map { chr(length $_).$_ } split /\./, $node, -1);
}

sub C(@) { # "Colon"
    join(':', @_)
}

my @domain;
sub domain($$) {
    my ($package, $domain, $entries) = @_;

    my $ttl = interval($config{default_ttl});
    my @conf = map { ;
                     my $rr = lc $_->type;
                     my $fqdn = $_->name . '.';

                     $rr eq 'a'     ? '='.C($fqdn,$_->address,$ttl) :
                     $rr eq 'cname' ? 'C'.C($fqdn,$_->cname.'.',$ttl) :
                     $rr eq 'rp'    ? ':'.C($fqdn,17,tiny_escape(domainname_encode(email($_->mbox)).domainname_encode($_->txtdname)),$ttl) :
                     $rr eq 'mx'    ? '@'.C($fqdn,'',$_->exchange.'.',$_->preference,'',$ttl) :
                     $rr eq 'ns'    ? '&'.C($fqdn,'',$_->nsdname.'.',$ttl) :
                     $rr eq 'txt'   ? "'".C($fqdn,tiny_escape(join('',$_->char_str_list)),$ttl) :
                     $rr eq 'soa'   ? 'Z'.C($fqdn,
                                            $_->mname.'.',
                                            email($_->rname),
                                            $_->serial || '',
                                            $_->refresh, $_->retry, $_->expire, $_->minimum, $ttl) :
                     $rr eq 'srv'   ? ':'.C($fqdn,33,tiny_escape(pack("nnn", $_->priority, $_->weight, $_->port)
                                                                 .domainname_encode($_->target)),$ttl) :
                        die "Don't know how to handle \"$rr\" RRs yet.";

                   } @$entries;

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
