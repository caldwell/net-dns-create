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

sub txt(@) {
    map { "\"$_\"" } @_;
}

sub group_by_type_and_name($$) {
    my ($re, $entries) = @_;
    my %set;
    for my $r (grep { lc($_->type) =~ $re } @$entries) {
        push @{$set{$r->type .'_'. $r->name}}, $r;
    }
    map { $set{$_} } keys %set;
}

my @domain;
sub _domain() { @domain } # Hook for testing
sub domain($$) {
    my ($package, $domain, $entries) = @_;

    my $ttl = interval($config{default_ttl});

    my @entries = map { ;
                        my $rr = lc $_->type;

                        $rr eq 'soa' ? () : # Amazon manages its own SOA stuff. Just ignore things we might have.
                        $rr eq 'rp'  ? (warn("Amazon doesn't support RP records (or I don't know how to make them)") && ()) :

                        $rr eq 'mx' || $rr eq 'ns' || $rr eq 'srv' || $rr eq 'txt' ? () : # Handled specially, below

                        +{
                          action => 'create',
                          name   => $_->name.'.',
                          ttl    => $ttl,
                          type   => uc $rr,
                          $rr eq 'a'     ? (value => $_->address) :
                          $rr eq 'cname' ? (value => $_->cname.'.') :
                          (err => warn "Don't know how to handle \"$rr\" RRs yet.")

                         }
                    } @$entries;

    # Amazon wants all NS,MX,TXT and SRV entries for a particular name in one of their entries. We get them in as
    # separate entries so first we have to group them together.
    push @entries, map { my @set = @$_;
                         my $rr = lc $set[0]->type;
                         $rr eq 'ns' && $set[0]->name.'.' eq $domain ? () : # Amazon manages its own NS stuff. Just ignore things we might have.
                         +{
                           action => 'create',
                           name   => $set[0]->name.'.',
                           ttl    => $ttl,
                           type   => uc $rr,
                           $rr eq 'mx'    ? (records => [map { $_->preference." ".$_->exchange.'.' } @set]) :
                           $rr eq 'ns'    ? (records => [map { $_->nsdname.'.' } @set] ) :
                           $rr eq 'srv'   ? (records => [map { $_->priority ." ".$_->weight ." ".$_->port ." ".$_->target.'.' } @set]) :
                           $rr eq 'txt'   ? (records => [map { join ' ', txt($_->char_str_list) } @set]) :
                           (err => die uc($rr)." can't happen here!")
                          }
                       } group_by_type_and_name(qr/^(?:mx|ns|srv|txt)$/, $entries);

    push @domain, { name => $domain,
                    entries => \@entries };
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
