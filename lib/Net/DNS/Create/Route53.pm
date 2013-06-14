#  Copyright (c) 2013 David Caldwell,  All Rights Reserved. -*- cperl -*-

package Net::DNS::Create::Route53;
use feature ':5.10';
use strict;
use warnings;

use Net::DNS::Create qw(internal full_host email interval);
use Net::Amazon::Route53;

our %config = (default_ttl=>'1h');
sub import {
    my $package = shift;
    my %c = @_;
    $config{$_} = $c{$_} for keys %c;
}

my $r53;
sub r53() {
    $r53 //= Net::Amazon::Route53->new(id  => $config{amazon_id},
                                       key => $config{amazon_key});
}

my $zones;
sub hosted_zone($) {
    # The eval works around a bug in Net::Amazon::Route53 where it dies if there are no zones at all.
    $zones = eval { [r53->get_hosted_zones()] } || []  unless defined $zones;
    (grep { $_->name eq $_[0] } @$zones)[0] // undef;
}

sub txt($) {
    my ($t) = @_;
    return "\"$t\"" if length $t < 255;
    my @part;
    push @part, $1 while ($t =~ s/^(.{255})//);
    map { "\"$_\"" } @part, $t;
}

my @domain;
sub domain($$) {
    my ($package, $domain, $entries) = @_;

    my $fq_domain = "$domain.";

    my $ttl = interval($config{default_ttl});

    push @domain, { name => $fq_domain,
                    entries => [
                                map { my $node = $_;
                                      my $fqdn = full_host($_,$domain);
                                      $fqdn =~ s/^@\.//;
                                      map {
                                          my $rr = lc $_;
                                          my $val = $entries->{$node}->{$_};

                                          $rr eq 'soa' ? () : # Amazon manages its own SOA stuff. Just ignore things we might have.
                                          $rr eq 'rp'  ? (warn("Amazon doesn't support RP records (or I don't know how to make them)") && ()) :
                                          $rr eq 'ns' && $node eq '@' ? () : # Amazon manages its own NS stuff. Just ignore things we might have.
                                          +{
                                            action => 'create',
                                            name   => $fqdn,
                                            ttl    => $ttl,
                                            type   => uc $rr,
                                            $rr eq 'a'     ? (value => $val) :
                                            $rr eq 'cname' ? (value => $val) :
                                            $rr eq 'mx'    ? (records => [map { "$_ $val->{$_}" } keys %$val] ) :
                                            $rr eq 'ns'    ? (records => [@$val] ) :
                                            $rr eq 'txt'   ? (records => [txt($val)] ) :
                                            $rr eq 'srv'   ? (records => [map { my $target = $_;
                                                                                map {
                                                                                     ($_->{priority} // "0")
                                                                                     ." ".($_->{weight} // "0")
                                                                                     ." ".($_->{port})
                                                                                     ." ".$target
                                                                                    } (ref $val->{$_} eq 'ARRAY' ? @{$val->{$_}} : $val->{$_})
                                                                              } keys %$val] ) :
                                            (err => die "Don't know how to handle \"$rr\" RRs yet.")

                                           }
                                      } keys %{$entries->{$node}}
                                } keys %$entries] };
}

my $counter = rand(1000);
sub master() {
    my ($package) = @_;
    local $|=1;

    for my $domain (@domain) {
        my $zone = hosted_zone(full_host($domain->{name}));
        if (!$zone && scalar @{$domain->{entries}}) {
            my $hostedzone = Net::Amazon::Route53::HostedZone->new(route53 => r53,
                                                                   name => $domain->{name},
                                                                   comment=>(getpwuid($<))[0].'/'.__PACKAGE__,
                                                                   callerreference=>__PACKAGE__."-".localtime."-".($counter++));
            print "New Zone: $domain->{name}...";
            $hostedzone->create();
            $zone = $hostedzone;
            print "Created\n";
        }

        if ($zone) {
            my $current = [ grep { $_->type ne 'SOA' && ($_->type ne 'NS' || $_->name ne $domain->{name}) } @{$zone->resource_record_sets} ];
            my $new = [ map { Net::Amazon::Route53::ResourceRecordSet->new(%{$_},
                                                                           values => [$_->{value} // @{$_->{records}}],
                                                                           route53 => r53,
                                                                           hostedzone => $zone) } @{$domain->{entries}} ];
            printf "%s: %d -> %d\n", $domain->{name}, scalar @$current, scalar @$new;
            my $change = scalar @$current > 0 ? r53->atomic_update($current,$new) :
                         scalar @$new     > 0 ? r53->batch_create($new)           :
                                                undef;

            unless (scalar @{$domain->{entries}}) {
                print "Deleting $domain->{name}\n";
                $zone->delete;
            }
        }
    }
}

sub domain_list($@) {
    my $zone = hosted_zone(full_host($_[0]));
    printf "%-30s %s\n", $zone ? $zone->id : '', $_[0];
}

sub master_list($$) {
    # This doesn't really make sense in the route53 context
}

1;
