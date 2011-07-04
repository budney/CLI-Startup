# Basic API tests

use Test::More;
use Test::Trap;
use Test::Exception;

use CLI::Startup;

my $app = CLI::Startup->new;

# Some calls aren't allowed AT ALL
ok !$app->can('set_config'),     "<config> attribute not settable";
ok !$app->can('set_options'),    "<options> attribute not settable";
ok !$app->can('set_initalized'), "<initialized> attribute not settable";

# Some calls aren't allowed /before/ init
throws_ok { $app->get_config  } qr/before init/, "get_config() before init()";
throws_ok { $app->get_options } qr/before init/, "get_options() before init()";

# This call should fail because options weren't defined yet.
throws_ok { $app->die_usage } qr/FATAL/, "die_usage() with no options";

# These calls should fail due to incorrect arguments
throws_ok { $app->set_optspec } qr/requires a hashref/,
    "set_optspec() requires a hashref";
throws_ok { $app->set_write_rcfile(1) } qr/requires a coderef/,
    "set_write_rcfile() requires a coderef";

# These calls should all live
lives_ok { $app->set_usage('')             } "set_usage() lives";
lives_ok { $app->set_rcfile('')            } "set_rcfile() lives";
lives_ok { $app->set_optspec({foo=>'bar'}) } "set_optspec() lives";
lives_ok { $app->set_write_rcfile('')      } "set_write_rcfile() lives";

# Now call init()
lives_ok { $app->init } "init() lives the first time";

# Now that options were set, die_usage() should succeed--which means
# that it should die with a usage message.
trap { $app->die_usage };
ok $trap->stderr =~ /usage:/, "die_usage() succeeds";
ok $trap->stdout eq '', "Nothing printed to stdout";
ok $trap->exit == 1, "Correct exit status";

# Some calls aren't allowed /after/ init
my $dies = "dies after init()";
throws_ok { $app->init             } qr/second time/, "init() $dies";
throws_ok { $app->set_usage        } qr/after init/,  "set_usage() $dies";
throws_ok { $app->set_rcfile       } qr/after init/,  "set_rcfile() $dies";
throws_ok { $app->set_optspec({})  } qr/after init/,  "set_optspec() $dies";
throws_ok { $app->set_write_rcfile } qr/after init/,  "set_write_rcfile() $dies";

done_testing();
