use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'CLI::Startup',
    license             => 'perl',
    dist_author         => q{Len Budney <len.budney@gmail.com>},
    dist_version_from   => 'lib/CLI/Startup.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'CLI-Startup-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
