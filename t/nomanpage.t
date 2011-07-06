# Test the print_manpage functionality with no POD

use Test::More;
use Test::Trap;

eval "use CLI::Startup 'startup'";
plan skip_all => "Can't load CLI::Startup" if $@;

# Simulate an invocation with --manpage
{
    local @ARGV = ('--manpage');

    trap { startup({ x => 'dummy option' }) };
    ok $trap->exit == 1, "Error exit";
    ok $trap->stderr, "Error message printed";
    like $trap->stderr, qr/usage:/, "Usage message printed";
}

done_testing();

__END__
