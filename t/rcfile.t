# Test reading and writing of RC files

use Test::More;

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

# Clean up
unlink $rcfile;
unlink "$rcfile.check";
rmdir "$dir/tmp";

done_testing();
