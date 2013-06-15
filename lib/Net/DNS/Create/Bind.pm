#  Copyright (c) 2009 David Caldwell,  All Rights Reserved. -*- cperl -*-

package Net::DNS::Create::Bind;
use Net::DNS::Create qw(internal full_host local_host email interval);
use feature ':5.10';
use strict;
use warnings;

use POSIX qw(strftime);
use File::Slurp qw(write_file);

our %config = (conf_prefix=>'', default_ttl=>'1h', dest_dir=>'.');
sub import {
    my $package = shift;
    my %c = @_;
    $config{$_} = $c{$_} for keys %c;
}

sub txt(@) {
    return "\"$_[0]\"" if scalar @_ == 1;
    '('.join("\n" . " " x 41, map { "\"$_\"" } @_).')';
}

our @zone;
sub domain {
    my ($package, $domain, $entries) = @_;

    my $conf = '$TTL  '.interval($config{default_ttl})."\n".
               join '', map { ;
                              my $rr = lc $_->type;
                              my $prefix = sprintf "%-30s in %-5s", local_host($_->name, $domain), $rr;

                              $rr eq 'mx'  ? "$prefix ".$_->preference." ".local_host($_->exchange, $domain)."\n" :
                              $rr eq 'ns'  ? "$prefix ".local_host($_->nsdname, $domain)."\n" :
                              $rr eq 'txt' ? "$prefix ".txt($_->char_str_list)."\n" :
                              $rr eq 'srv' ? "$prefix ".join(' ', $_->priority, $_->weight, $_->port, local_host($_->target, $domain))."\n" :
                              $rr eq 'rp'  ? "$prefix ".local_host(email($_->mbox), $domain)." ".local_host($_->txtdname, $domain)."\n" :
                              $rr eq 'soa' ? "$prefix ".join(' ', local_host($_->mname, $domain),
                                                                  local_host(email($_->rname), $domain),
                                                             '(',
                                                                  $_->serial || strftime('%g%m%d%H%M', localtime),
                                                                  $_->refresh,
                                                                  $_->retry,
                                                                  $_->expire,
                                                                  $_->minimum,
                                                             ')')."\n" :
                              $rr eq 'a'     ? "$prefix ".$_->address."\n" :
                              $rr eq 'cname' ? "$prefix ".local_host($_->cname, $domain)."\n" :
                                  die __PACKAGE__." doesn't handle $rr record types";
                          } @$entries;

    my $conf_name = "$config{dest_dir}/$config{conf_prefix}$domain.zone";
    $conf_name =~ s/\.\././g;
    push @zone, { conf => $conf_name, domain => $domain };
    write_file($conf_name, $conf);
}

sub master {
    my ($package, $filename, $prefix, @extra) = @_;
    $prefix //= '';
    my $master_file_name = "$config{dest_dir}/$config{conf_prefix}$filename";
    write_file($master_file_name,
               @extra,
               map { <<EOZ
zone "$_->{domain}" {
    type master;
    file "$prefix$_->{conf}";
};

EOZ
               } @zone);
    system("named-checkconf", "-z", $master_file_name);
}

sub domain_list($@) {
    print "$config{conf_prefix}$_[0].zone\n";
}

sub master_list($$) {
    print "$config{conf_prefix}$_[0]\n"
}

1;
