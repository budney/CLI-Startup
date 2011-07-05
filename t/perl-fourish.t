# Test the non-object-oriented interface

use Test::More;
use Test::Trap;

eval "use CLI::Startup 'startup'";
plan skip_all => "Can't load CLI::Startup" if $@;

# Test that the sub was imported
ok defined(&startup), "startup() was exported";

# Trivial command-line flag
{
    local @ARGV = ('--verbose');
    my $options = startup({
        verbose => 'Print verbose output',
    });
    ok $options->{verbose} || 0, "--verbose option read correctly";
}

# Bad options cause usage message
{
    my $options;

    local @ARGV = ('--foo');
    trap { startup({ bar => 'bar option' }) };

    ok $trap->exit == 1, "Error status on invalid option";
    like $trap->stderr, qr/usage:/, "Usage message printed";
}

# --help option automatically causes usage message
{
    local @ARGV = ('--help');
    trap { startup({ foo => 'foo option' }) };

    ok $trap->exit == 1, "Correct exit status on --help option";
    like $trap->stderr, qr/usage:/, "Usage message printed";
}

# --help option with custom help text and usage
{
    local @ARGV = ('--help');
    trap { startup({ help => 'custom help', foo => 'bar' })};

    ok $trap->exit == 1, "Correct exit status on --help";
    like $trap->stderr, qr/custom help/, "Custom help message printed";
}

# --rcfile option with rcfile disabled
{
    local @ARGV = ('--rcfile=/foo');
    trap { startup({ rcfile => undef, foo => 'bar' })};

    ok $trap->exit == 1, "Error status with disabled --rcfile";
    like $trap->stderr, qr/usage:/, "Usage message printed";
}

# --write-rcfile option with rcfile diabled
{
    local @ARGV = ('--write-rcfile');
    trap { startup({ 'write-rcfile' => undef, foo => 'bar' }) };

    ok $trap->exit == 1, "Error status with disabled --write-rcfile";
    like $trap->stderr, qr/usage:/, "Usage message printed";
    like $trap->stderr, qr/rcfile/, "--rcfile shown in help";
    unlike $trap->stderr, qr/write-rcfile.*Write options/,
        "--write-rcfile not shown";
}

# --help option defined twice
{
    trap { startup({ help => 'first', 'help=s' => 'second' }) };

    ok $trap->leaveby eq 'die', "Error exit with twice-defined option";
    like $trap->die, qr/defined twice/, "Error message printed";
}

# Invalid prototypes for default options
{
    for my $spec (qw/ help=s write-rcfile=s rcfile=i /)
    {
        trap { startup({ $spec => 'foo', bar => 'baz' }) };

        ok $trap->leaveby eq 'die', "Error exit with invalid spec: $spec";
        like $trap->die, qr/defined incorrectly/i, "Error message printed";
    }
}

done_testing();
