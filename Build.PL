use 5.008;
use strict;
use warnings FATAL => 'all';
use Module::Build;

if (-d ".git") { # Are we in our development tree? If so, create MANIFEST.
    my ($dir, $manifest);
    open $manifest, ">", "MANIFEST" or die "MANIFEST: $!";
    print $manifest "MANIFEST\n";
    open $dir, '-|', 'git', 'ls-files' or die "Couldn't run git: $!";
    while (<$dir>) { print $manifest $_ }
}

my $builder = Module::Build->new(
    module_name         => 'Net::DNS::Create',
    license             => 'perl',
    dist_author         => q{David Caldwell <david@porkrind.org>},
    dist_version_from   => 'lib/Net/DNS/Create.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Hash::Merge::Simple'  => 0,
        'Net::DNS'             => '0.72',
        'Net::Amazon::Route53' => 0,
        'LWP::Protocol::https' => 0, # Should probably be required by Net::Amazon::Route53
    },
);

$builder->create_build_script();