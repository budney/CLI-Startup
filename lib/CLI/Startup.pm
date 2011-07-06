package CLI::Startup;

use warnings;
use strict;

use Symbol;
use Pod::Text;
use Text::CSV;
use Class::Std;
use Getopt::Long;
use Config::Simple;
use File::Basename;
use Clone qw{ clone };
use List::Util qw{ max };

use Exporter;
our @ISA       = qw/Exporter/;
our @EXPORT_OK = qw/startup/;

=head1 NAME

CLI::Startup - Simple initialization for command-line scripts

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Every command-line script does (or should) accept command-line
options, at the very least a C<--help> option, and should allow
default options to be specified in a "resource" file, named by
default C<$HOME/.SCRIPTNAMErc>.

This package accepts a simple hash of command-line options and
uses it to generate command-line processing, a C<--help> message,
and resource-file processing. These are all annoying chores that
every script needs, and that are always essentially identical but
for the specific options supported.

    use CLI::Startup;

    my $app = CLI::Startup->new({
        'infile=s'   => 'An option for specifying an input file',
        'outfile=s'  => 'An option for specifying an output file',
        'password=s" => 'A password to use for something',
        'email=s@'   => 'Some email addresses to notify of something',
        'verbose'    => 'Verbose output flag',
        'lines:i'    => 'Optional - the number of lines to process',
        'retries:5'  => 'Optional - number of retries; defaults to 5',
        ...
    });

    # Process the command line and resource file (if any)
    $app->init;

    # Handle program options, which might have come from the
    # command line, or might have come from the resource file:
    my %opts    = $app->get_options;
    my $opts    = $app->get_options;            # Can return hash or hashref
    my $verbose = $app->get_options('verbose'); # Can look up individual opts
    my @email   = $app->get_options('email');   # Can return array or arrayref
    ...

    # Print messages to the user, with helpful formatting
    print $app->usage(); # Print the --help message
    $app->die_usage();   # Print the --help message and exit
    $app->warn();        # Format warnings nicely
    $app->die();         # Die with a nicely-formatted message

=head1 EXPORT

If you really don't like object-oriented coding, or your needs are
super-simple, C<CLI::Startup> exports a single method: C<startup>.

=head2 startup

  my %opts = startup({
    'opt1=s' => 'Option taking a string',
    'opt2:i' => 'Optional option taking an integer',
    ...
  });

Process command-line options specified in the argument hash.
Automatically responds to the C<--help> option, or to invalid
options, by printing a help message and exiting. Otherwise returns
a hash (or hashref, depending on the calling context) of the options
requested. Automatically checks for default options in a resource
file named C<$HOME/.SCRIPTNAMErc>.

If you want any fancy configuration, or you want to customize any
behaviors, then you need to use the object-oriented interface.

=cut

sub startup
{
    my $optspec = shift;

    my $app = CLI::Startup->new($optspec);
    $app->init;

    return $app->get_options;
}

=head1 ACCESSORS

=head2 get_config

  $config = $app->get_config;

Returns the contents of the resource file as a hashref. This
attribute is read-only; it is set when the config file is read,
which happens when C<$app->init()> is called.

It is a fatal error to call C<get_config()> before C<init()> is
called.

=cut

my %config_of : ATTR();

sub get_config
{
    my $self = shift;
    $self->die("get_config() called before init()")
        unless $self->get_initialized;
    return $config_of{ident $self};
}

=head2 get_initialized

  $app->init unless $app->get_initialized();

Read-only flag indicating whether the app is initialized. This is
used internally; you probably shouldn't need it since you should
only be calling C<$app->init()> once, near the start of your script.

=cut

my %initialized_of :ATTR( :get<initialized> );

=head2 get_options

  my %options = $app->get_options;

Read-only: the command options for the current invocation of the
script. This includes the actual command-line options of the script,
or the defaults found in the config file, if any, or the wired-in
defaults from the script itself, in that order of precedence.

Usually, this information is all your script really cares about
this. It doesn't care about C<$app->get_config> or C<$app->get_optspec>
or any other building blocks that were used to ultimately build
C<$app->get_options>.

It is a fatal error to call C<get_options()> before calling C<init()>.

=cut 

my %options_of :ATTR();

sub get_options
{
    my $self = shift;
    $self->die("get_options() called before init()")
        unless $self->get_initialized;
    return $options_of{ident $self};
}

=head2 get_optspec

  my $optspec = $app->get_optspec();

Returns the hash of command-line options. See C<set_optspec>
for an example, and see C<Getopt::Long> for the full syntax.

=head2 set_optspec

  $app->set_optspec({
    'file=s'  => 'File to read',    # Option with string argument
    'verbose' => 'Verbose output',  # Boolean option
    'tries=i' => 'Number of tries', # Option with integer argument
    ...
  });

Set the hash of command-line options. The keys use C<Getopt::Long>
syntax, and the values are descriptions for printing in the usage
message.

It is an error to call C<set_optspec()> after calling C<init()>.

=cut

my %optspec_of : ATTR( :get<optspec> :initarg<optspec> );

sub set_optspec
{
    my $self = shift;
    my $spec = shift;

    $self->die("set_optspec() requires a hashref")
        unless ref $spec eq 'HASH';
    $self->die("set_optspec() called after init()")
        if $self->get_initialized;

    $optspec_of{ident $self} = clone($self->_validate_optspec($spec));
}

=head2 get_rcfile

  my $path = $app->get_rcfile;

Get the full path of the rcfile to read or write.

=head2 set_rcfile

  $app->set_rcfile( $path_to_rcfile );

Set the path to the rcfile to read or write. This overrides the
build-in default of C<$HOME/.SCRIPTNAMErc>, but is in turn overridden
by the C<--rcfile> option supported automatically by C<CLI::Startup>.

It is an error to call C<set_rcfile()> after calling C<init()>.

=cut

my %rcfile_of : ATTR( :get<rcfile> :initarg<rcfile> );

sub set_rcfile
{
    my ($self, $rcfile) = @_;

    $self->die("set_optspec() called after init()")
        if $self->get_initialized;
    $rcfile_of{ident $self} = "$rcfile";
}

=head2 get_usage

  print "Usage: $0: " . $app->get_usage . "\n";

Returns the usage string printed as part of the C<--help>
output. Unlikely to be useful outside the module.

=head2 set_usage

  $app->set_usage("[options] FILE1 [FILE2 ...]");

Set a usage message for the script. Useful if the command options are
followed by positional parameters; otherwise a default usage message
is supplied automatically.

It is an error to call C<set_usage()> after calling C<init()>.

=cut

my %usage_of : ATTR( :get<usage> :initarg<usage> );

sub set_usage
{
    my ($self, $usage) = @_;

    $self->die("set_usage() called after init()")
        if $self->get_initialized;
    $usage_of{ident $self} = "$usage";
}

=head2 set_write_rcfile

  $app->set_write_rcfile( \&rcfile_writing_sub );

A code reference for writing out the rc file, in case it has
extra options needed by the app. Setting this to C<undef>
disables the C<--write-rcfile> command-line option. This option
is also disabled if I<reading> rc files is disabled by setting
the C<rcfile> attribute to undef.

It is an error to call C<set_write_rcfile()> after calling C<init()>.

=cut

my %write_rcfile_of : ATTR( :get<write_rcfile> :initarg<write_rcfile> );

sub set_write_rcfile
{
    my $self   = shift;
    my $writer = shift || 0;

    $self->die("set_write_rcfile() called after init()")
        if $self->get_initialized;
    $self->die("set_write_rcfile() requires a coderef or false")
        if $writer && ref($writer) ne 'CODE';

    # Toggle the --write-rcfile option spec if writing is toggled
    my $optspec = $optspec_of{ident $self}; # Need a reference, not a copy
    if ($writer)
    {
        $optspec->{'write-rcfile'} ||= 'Write options to rcfile';
    }
    else
    {
        delete $optspec->{'write-rcfile'};
    }

    # Save the writer
    $write_rcfile_of{ident $self} = $writer;
}

=head1 SUBROUTINES/METHODS

=head2 die

  $app->die("die message");
  # Prints the following, for script "$BINDIR/foo":
  # foo: FATAL: die message

Die with a nicely-formatted message, identifying the script that
died.

=cut

sub die
{
    my $self = shift;
    my $msg  = shift;
    my $name = basename($0);

    CORE::die "$name: FATAL: $msg\n";
}

=head2 die_usage

  $app->die_usage if $something_wrong;

Print a help message and exit. This is called internally if the user
supplies a C<--help> option on the command-line.

=cut

sub die_usage
{
    my $self    = shift;
    my $optspec = $self->get_optspec;

    # Keep only the options that are actually used, and
    # sort them in dictionary order.
    my %options =
        map { m/([^=:]+)[=:]?/; {$1, $_} }
        keys %$optspec;
    $self->die("die_usage() called without defining any options")
        unless keys %$optspec;

    # Note the length of the longest option
    my $length  = max map { length($_) } keys %options;

    # Now print the help message.
    print  STDERR basename($0) . ": usage:\n";
    print  STDERR basename($0) . " " . $self->get_usage . "\n";
    printf STDERR "    %-${length}s - %s\n", $_, $optspec->{$options{$_}}
        for sort keys %options;

    exit 1;
}

# Returns the "default" optspec, consisting of options
# that CLI::Startup normally creates automatically.
sub _default_optspec
{
    return {
        'help'          => 'Print this helpful help message',
        'rcfile=s'      => 'Config file to load',
        'write-rcfile'  => 'Write current options to rcfile',
        'version'       => 'Print version information and exit',
        'manpage'       => 'Print the manpage for this script',
    };
}

# Breaks an option spec down into its components.
sub _parse_spec
{
    my ($self, $spec) = @_;

    # We really want the "name(s)" portion
    $spec =~ /^([^:=!+]+)([:=!+]?).*([@%]?).*$/;

    return {
        spec  => $spec,
        names => [ split /\|/, $1 ],
        list  => ( $3 eq '@'             ? 1 : 0 ),
        hash  => ( $3 eq '%'             ? 1 : 0 ),
        bool  => ( $2 eq '' || $2 eq '!' ? 1 : 0 ),
        flag  => ( $2 eq ''              ? 1 : 0 ),
    };
}

# Returns a hash of option names and specs from the supplied
# hash. Also converts undef to 0 in $optspec.
sub _option_specs
{
    my ($self, $optspec ) = @_;
    my %option_specs;

    # Make sure that there are no duplicated option names,
    # and that options with undefined help text are defined
    # to false.
    for my $option (keys %$optspec)
    {
        $optspec->{$option} ||= 0;
        $option               = $self->_parse_spec($option);

        # The spec can define aliases
        for my $name ( @{ $option->{names} } )
        {
            $self->die("--$name option defined twice") if exists $option_specs{$name};
            $option_specs{$name} = $option->{spec};
        }
    }

    return \%option_specs;
}

# Returns an options spec hashref, with automatic options
# added in.
sub _validate_optspec
{
    my ( $self, $optspec ) = @_;

    # Build a hash of option specs in $optspec, indexed by option name.
    # Die with an error if any option names collide.
    my $option_specs  = $self->_option_specs($optspec);
    my $defaults      = $self->_default_optspec;
    my $default_specs = $self->_option_specs($defaults);

    # Verify that any default options specified in $optspec are specified
    # with the right signature OR are bare words. This makes for the
    # syntactic sugar of saying { rcfile => 0 } instead of { 'rcfile=s' => 0 }.
    for my $name ( keys %$default_specs )
    {
        # If the option isn't mentioned, then set it to the default.
        if ( not exists $option_specs->{$name} )
        {
            my $spec = $default_specs->{$name};
            $optspec->{$spec} = $defaults->{$spec};
            next;
        }
        my $spec = delete $option_specs->{$name};

        # Noting more to do if the specs match
        next if $spec eq $default_specs->{$name};

        # Otherwise it's a fatal error for the spec to be more than a bare word,
        # possibly with aliases.
        $spec = $self->_parse_spec($spec);
        $self->die("--$name option defined incorrectly") unless $spec->{flag};

        # Forget the aliases for default options
        delete $option_specs->{$_} for @{ $spec->{names} };

        # Delete the default spec for this option, since it's
        # redundant with the spec we found.
        delete $optspec->{$default_specs->{$name}};
    }

    # Make sure there's at least one option left
    $self->die("No command-line options defined") unless keys %$option_specs;

    # The --help option is NOT optional
    $optspec->{help} = $defaults->{help} unless $optspec->{help};

    # Remove disabled options
    map { delete $optspec->{$_} unless $optspec->{$_} } keys %$optspec;

    return $optspec;
}

=head2 init

  $app  = CLI::Startup->new( \%optspec );
  $app->init;
  $opts = $app->get_options;

Initialize command options by parsing the command line and merging in
defaults from the rcfile, if any. This is where most of the work gets
done. If you don't have any special needs, and want to use the Perl
fourish interface, the C<startup()> function basically does nothing
more than the example code above.

=cut

sub init {
    my $self = shift;

    $self->die("init() method takes no arguments") if @_;
    $self->die("init() called a second time")
        if $self->get_initialized;

    # It's a fatal error to call init() without defining any
    # command-line options
    $self->die("init() called without defining any command-line options")
        unless $self->get_optspec || 0;

    # Parse command-line options, then read the config file if any.
    my $options = $self->_process_command_line;
    my $config  = $self->_read_config_file;

    # Now, merge the defaults with the command-line options.
    for my $option ( keys %{$config->{default}} )
    {
        next if exists $options->{$option};
        $options->{$option} = $config->{default}{$option};
    }

    # Save the fully-processed options
    $options_of{ident $self} = $options;

    # Mark the object as initialized
    $initialized_of{ident $self} = 1;

    #
    # Automatically processed options:
    #

    # Write back the config if requested
    $self->write_rcfile if $options->{'write-rcfile'};

    # Print the POD manpage from the script, if requested
    $self->print_manpage if $options->{manpage};
}

sub _process_command_line
{
    my $self    = shift;
    my $optspec = $self->get_optspec;
    my %options;

    # Parse the command line and die if anything is wrong.
    my $opts_ok = GetOptions( \%options, keys %$optspec );
    $self->die_usage if $options{help} || !$opts_ok ;

    # Treat list and hash options as CSV records, so we can
    # cope with quoting and values containing commas.
    my $csv = Text::CSV->new({ allow_loose_quotes => 1 });

    # Further process the array and hash options
    for my $option (keys %options)
    {
        if ( ref $options{$option} eq 'ARRAY' )
        {
            my @values;
            for my $value (@{$options{$option}})
            {
                $csv->parse($value)
                    or $self->die("Can't parse --$option option: $value");
                push @values, $csv->fields;
            }

            $options{$option} = \@values;
        }
    }

    # Process the rcfile option immediately, to override any settings
    # hard-wired in the app, as well as this module's defaults.
    $self->set_rcfile($options{rcfile}) if defined $options{rcfile};

    # That's it!
    return \%options;
}

sub _read_config_file
{
    my $self = shift;

    my $rcfile = $self->get_rcfile || '';
    $rcfile
        = $rcfile && -r $rcfile
        ? Config::Simple->new($rcfile)
        : '';

    # Extract the contents of the config
    my $raw_config = $rcfile ? $rcfile->vars() : {};
    my ($defaults, $config) = ( {}, {} );

    # Now, in case the config file has sections, unflatten the hash.
    for my $option ( keys %$raw_config )
    {
        if ( $option =~ /^(.*)\.(.*)$/ )
        {
            $config->{$1}     ||= {};
            $config->{$1}{$2}   = $raw_config->{$option};
        }
        else
        {
            $defaults->{$option} = $raw_config->{$option};
        }
    }
    $config->{default} = $defaults unless $config->{default};

    # Save the unflattened config for reference
    $config_of{ident $self} = $config;

    return $config;
}

=head2 new

  # Normal: accept defaults and specify only options
  my $app = CLI::Startup->new( \%options );

  # Advanced: override some CLI::Startup defaults
  my $app = CLI::Startup->new(
    rcfile       => $rcfile_path, # Set to false to disable rc files
    write_rcfile => \&write_sub,  # Set to false to disable writing
    optspec => \%options,
  );

Create a new C<CLI::Startup> object to process the options
defined in C<\%options>.

=head2 BUILD

An internal method called by C<new()>.

=cut

sub BUILD {
    my ($self, $id, $argref) = @_;

    # Shorthand: { options => \%options } can be
    # abbreviated \%options.
    if ( not exists $argref->{options} )
    {
        $argref = { options => $argref };
    }
    $self->set_optspec($argref->{options}) if keys %{$argref->{options} || {}};

    # Caller can override the default rcfile. Setting this to
    # undef disables rcfile reading for the script.
    $self->set_rcfile(
          exists $argref->{rcfile}
        ? $argref->{rcfile}
        : "$ENV{HOME}/." . basename($0) . "rc"
    );

    # Caller can forbid writing of rcfiles by setting
    # the write_rcfile option to undef, or can supply
    # a coderef to do the writing.
    if ( exists $argref->{write_rcfile} )
    {
        $self->set_write_rcfile( $argref->{write_rcfile} );
    }

    # Set an optional usage message for the script.
    $self->set_usage(
          exists $argref->{usage}
        ? $argref->{usage}
        : "[options]"
    );
}

=head2 print_manpage

  $app->print_manpage;

Prints the formatted POD contained in the calling script.
If there's no POD content in the file, then the C<--help>
usage is printed instead.

=cut

sub print_manpage
{
    my $self   = shift;
    my $parser = Pod::Text->new;

    $parser->output_fh(*STDERR);
    $parser->parse_file($0);
    $self->die_usage unless $parser->content_seen;

    exit 0;
}

=head2 warn

  $app->warn("warning message");
  # Prints the following, for script "$BINDIR/foo":
  # foo: WARNING: warning message

Print a nicely-formatted warning message, identifying the script
by name.

=cut

sub warn
{
    my $self = shift;
    my $msg  = shift;
    my $name = basename($0);

    warn "$name: WARNING: $msg\n";
}

=head2 write_rcfile

  $app->write_rcfile();      # Overwrite the rc file for this script
  $app->write_rcfile($path); # Write an rc file to a new location

Write the current settings for this script to an rcfile--by default,
the rcfile read for this script, but optionally a different file
specified by the caller. The automatic C<--write-rcfile> option
always writes to the script specified in the C<--rcfile> option.

It's a fatal error to call C<write_rcfile()> before calling C<init()>.

=cut

sub write_rcfile
{
    my $self = shift;

    # It's a fatal error to call write_rcfile() before init()
    $self->die("write_rcfile() called before init()")
        unless $self->get_initialized;

    # Check whether a writer has been set
    my $writer
        = exists $write_rcfile_of{ident $self}
        ? $write_rcfile_of{ident $self}
        : 1;

    # If there's a writer, call it.
    if ( ref $writer eq 'CODE' )
    {
        $writer->($self);
        return;
    }

    # If writing is disabled, abort.
    if ( not $writer )
    {
        $self->die("write_rcfile() disabled, but called anyway");
    }

    # If there's no file to write, abort.
    my $file = shift || $self->get_rcfile;
    $self->die("Write rcfile: no file specified") unless $file;

    # OK, continue with the built-in writer.
    my $conf = Config::Simple->new( syntax => 'ini' );

    my $settings = $self->get_config;
    my $options  = $self->get_options;

    # Copy the current options back into the "default"
    for my $option ( keys %$options )
    {
        next if $option eq 'rcfile';
        next if $option eq 'write-rcfile';
        $settings->{default}{$option} = $options->{$option};
    }

    # Flatten the settings back into the $conf object
    for my $key ( keys %$settings )
    {
        for my $setting ( keys %{ $settings->{$key} } )
        {
            $conf->param(
                "$key.$setting" => $settings->{$key}{$setting}
            );
        }
    }

    # Write back the results
    $conf->write($file);
}

=head1 AUTHOR

Len Budney, C<< <len.budney at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cli-startup at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CLI-Startup>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CLI::Startup

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CLI-Startup>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CLI-Startup>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CLI-Startup>

=item * Search CPAN

L<http://search.cpan.org/dist/CLI-Startup/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Len Budney.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of CLI::Startup
