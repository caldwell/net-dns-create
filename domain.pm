#  Copyright (c) 2011 David Caldwell,  All Rights Reserved. -*- cperl -*-

package domain;
use strict; use warnings;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(domain master soa);
our @EXPORT_OK = qw(domain master full_host email interval);

my $kind;
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
        @_ = ();
    }
    __PACKAGE__->export_to_level(1, $package, @_);
}

sub full_host($;$) { $_[0] =~ /\.$/ ? $_[0] : "$_[0]." . (defined $_[1] ? "$_[1]." : '') }

sub email($) {
    my ($email) = @_;
    $email =~ s/@/./g;
    full_host($email);
}

sub interval($) {
    $_[0] =~ /(\d+)([hmsdw])/ && $1 * { s=>1, m=>60, h=>3600, d=>3600*24, w=>3600*24*7 }->{$2} || $_[0];
}

use Hash::Merge::Simple qw(merge);
sub domain($@) {
    my ($domain, @entry_hashes) = @_;
    my $entries = {};
    for my $e (@entry_hashes) {
        $entries = merge($entries, $e);
    }
    $kind->domain($domain, $entries);
}

sub master {
    $kind->master(@_);
}

sub list() {
    no warnings;
    *domain = *main::domain = \&{"$kind\::domain_list"};
    *master = *main::master = \&{"$kind\::master_list"};
}


1;
