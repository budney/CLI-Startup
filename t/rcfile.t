# Test reading and writing of RC files

use Test::More;
use Test::Exception;

eval "use CLI::Startup";
plan skip_all => "Can't load CLI::Startup" if $@;

use Cwd;

# Create a temp directory
my $dir    = getcwd();
my $rcfile = "$dir/tmp/rcfile";
mkdir "$dir/tmp";

# Create an RC file
open RC, ">", $rcfile or die "Couldn't create $rcfile: $!";
print RC <<EOF;
[defaults]
foo=1
bar=baz
EOF
close RC or die "Couldn't write $rcfile: $!";

# Create a CLI::Startup object and read the rc file
my $app = CLI::Startup->new({
    rcfile  => $rcfile,
    options => {},
});
$app->init;

# Config file contents are stored now
is_deeply $app->get_config,  {defaults=>{foo=>1,bar=>'baz'}},
    "Config file contents";

# The "defaults" section of the config file is copied
# into the command-line options
is_deeply $app->get_options, {foo=>1,bar=>'baz'},
    "Command options contents";

# Write the current settings to a second file for comparison
$app->write_rcfile("$rcfile.check");

# Reading the resulting file should be idempotent
ok -r "$rcfile.check", "File was created";
my $app2 = CLI::Startup->new;
$app2->set_rcfile("$rcfile.check");
$app2->init;
is_deeply $app->get_config, $app2->get_config, "Config settings match";

# Reading a nonexistent file silently succeeds
my $app3 = CLI::Startup->new({ rcfile => "$dir/tmp/no_such_file" });
lives_ok { $app3->init } "Init with nonexistent file";
is_deeply $app3->get_config, { defaults => {} }, "Config is empty";

# Repeat the above, using arguments
{
    local @ARGV = ( "--rcfile=$dir/tmp/no_such_file" );
    my $app = CLI::Startup->new;
    lives_ok { $app->init } "Init with command-line rcfile";
    ok $app->get_rcfile eq "$dir/tmp/no_such_file", "rcfile set correctly";
    is_deeply $app->get_config, { defaults => {} }, "Config is empty";
}

# Now write back the config file and confirm the contents
{
    my $file = "$dir/tmp/auto";

    local @ARGV = (
        "--rcfile=$file", qw/ --write-rcfile --foo --bar=baz /
    );
    my $app = CLI::Startup->new({
        options => {
            foo     => 'foo option',
            'bar=s' => 'bar option',
        },
    });
    lives_ok { $app->init } "Init with nonexistent command-line rcfile";
    ok $app->get_rcfile eq "$file", "rcfile set correctly";
    is_deeply $app->get_config, {
        defaults => { foo=>1, bar=>'baz' }
    }, "Config is empty";
    ok -r "$file", "File was created";

    my $app2 = CLI::Startup->new({
        rcfile  => "$file",
        options => {},
    });
    $app2->init;
    is_deeply $app2->get_config, $app->get_config, "Writeback is idempotent";
}

# Clean up
unlink $_ for glob("$dir/tmp/*");
rmdir "$dir/tmp";

done_testing();
