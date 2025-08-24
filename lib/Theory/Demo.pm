package Theory::Demo;

# perl -nE '/^use ([^;\s]+)/ && say $1' lib/Demo.pm | xargs cpanm --notest

use strict;
use warnings;
use v5.28;
use Term::TermKey;
use IPC::System::Simple 1.17 qw(capturex run runx capture);
use WWW::Curl::Simple;
use IO::Socket::SSL;
use Net::SSLeay;
use JSON::PP;
use URI;
use utf8;
use open IN => ":encoding(utf8)", OUT => ":utf8";
use Encode qw(encode_utf8 decode_utf8);
use Term::ANSIColor ();
use Getopt::Long;
use File::Temp;

$| = 1;

=head1 Interface

=head2 Constructor

=head3 C<new>

Creates and returns new Demo object. Supported parameters:

=over

=item C<prompt>

String to use for the prompt. Defaults to "demo".

=item C<base_url>

The base URL to prepend to all requests.

=item C<ca_bundle>

Path to a PEM-encoded certificate authority bundle.

=item C<user>

Username to include in the Authorization header. Defaults to "demo".

=back

=cut

sub new {
    my ($pkg, %params) = @_;
    $params{curl} = WWW::Curl::Simple->new(
        check_ssl_certs => 1,
        ssl_cert_bundle => delete $params{ca_bundle},
    );
    $params{headers} = HTTP::Headers->new(
        #'Content-Type'  => 'application/json',
    );
    $params{headers}->authorization_basic('me');

    return bless {
        tk     => Term::TermKey->new( \*STDIN ),
        prompt => 'demo',
        user   => 'demo',
        head   => $headers,
        %params,
    } => $pkg;
}

=head2 Methods

=head3 C<bold>

Wraps arguments in ANSI bold, bright yellow formatting.

=cut

sub bold {
    shift;
    Term::ANSIColor::colored([qw(bold bright_yellow)], @_);
}

=head3 C<prompt>

Emits a prompt.

=cut

sub prompt {
    print "$_[0]->{prompt} > ";
}

=head3 C<nl_prompt>

Emits a newline and a prompt.

=cut

sub nl_prompt {
    print "\n$_[0]->{prompt} > ";
}

=head3 C<enter>

Waits for the user to hit the enter key.

=cut

sub enter {
    my $tk = shift->{tk};
    $tk->waitkey(my $key);
    while ($key->format(0) ne "Enter") {
        $tk->waitkey($key);
    }
    print "\n";
}

=head3 C<escape>

Waits for the user to hit the escape key.

=cut

sub escape {
    my $self = shift;
    $self->type_lines(@_);
    my $tk = $self->{tk};
    $tk->waitkey(my $key);
    while ($key->format(0) ne "Escape") {
        $tk->waitkey($key);
    }
    print "\n";
}

=head3 C<type>

Waits for the user to type any key and emits a single character of the the
arguments passed to it for each key. Unless the user hits the enter key, in
which case it will emit every character up to the next newline, then wait.
Returns when it has emitted all of the characters.

=cut

sub type {
    my $self = shift;
    my $tk = $self->{tk};
    my $str = encode_utf8 join ' ' => @_;
    for (my $i = 0; $i < length $str; $i++) {
        $tk->waitkey(my $k);
        my $c = substr $str, $i, 1;
        print $c;

        # Check for enter key.
        if ($k->format(0) eq 'Enter') {
            while ($c ne "\n" && $i < length $str) {
                print $c = substr $str, ++$i, 1;
            }
        }

        # Check for ANSI escape.
        if ($c eq "\e") {
            # Print until the escape close character.
            while ($c ne "m") {
                $c = substr $str, ++$i, 1;
                print $c;
            }
            # Print the first char after, if there is one.
            print substr $str, ++$i, 1 if $i < length $str;
        }
    }
    $self->enter;
}

=head3 C<comment>

Echoes its argumentsd then displays a prompt.

=cut


sub echo {
    my $self = shift;
    $self->type(@_);
    $self->prompt;
}

=head3 C<comment>

Echoes its arguments in bold and bright yellow, then displays a prompt.

=cut

sub comment {
    my $self = shift;
    $self->echo($self->bold(map { s/^/# /grm } @_));
}

sub start {
    my $self = shift;
    system 'clear';
    $self->prompt;
    if (@_) {
        $self->type($self->bold(map { s/^/# /grm } @_));
        $self->prompt;
    }
}

sub finish {
    my $self = shift;
    $self->type($self->bold(map { s/^/# /grm } @_)) if @_;
}

sub clear {
    my $self = shift;
    $self->type('clear');
    system 'clear';
    $self->prompt;
}

sub clear_now {
    system 'clear';
    shift->prompt;
}

$ENV{TMPDIR} =~ s{/+$}{};
my %env = %ENV;

sub _env {
    $_[0] =~ s/\$(\w+)/$env{$1} || $1/gerx if $_[0]
}

sub setenv {
    my $self = shift;
    my ($k, $v) = @_;
    $env{$k} = _env $v;
    $self->echo(qq{$k="$v"});
}


=head3 C<grab>

  my $version = $demo->grab(qw(uname -r));

Grab and return the output of a command.

=cut

sub grab() {
    shift;
    my $out = capturex @_;
    chomp $out;
    $out;
}

# Type out a list of lines to be "run", appending a backslash to all but the
# last, but without actually running anything. Emulates a multi-line shell
# command.
sub type_lines {
    my $self = shift;
    while (@_ > 1) {
        $self->type(shift(@_) . ' \\');
    }
    $self->type(shift);
}

# Types out a multi-line command and then runs it.
sub type_run {
    my $self = shift;
    $self->type_lines(@_);
    run _env join ' ', @_;
}

# Runs a multi-line command without first echoing it.
sub run_quiet {
    my $self = shift;
    run _env join ' ', @_;
}

# Like type_run, but captures the output of the command and replaces any string
# matching C<$ENV{TMPDIR}> wih F</tmp> before printing it, to avoid displaying
# the long, ugly macOS tmpdir name.
sub type_run_clean {
    my $self = shift;
    $self->type_lines(@_);
    for (capture _env join ' ', @_) {
        s{$ENV{TMPDIR}/*}{/tmp/}g;
        print;
    }
}

# Runs a JSON object through yq for pretty-printing.
sub _yq {
    my $fh = File::Temp->new;
    print {$fh} @_;
    runx qw(yq -oj), $fh->filename;
}

# Selects a path from a JSON JSON file using yq for pretty-printing.
sub yq {
    my ($self, $file, $path) = @_;
    $self->type_run(join ' ', 'yq -oj', ($path // '.'), $file);
    $self->nl_prompt;
}

# Diff two files. Requires `--color`; on macOS, `brew install diffutils`.
sub diff {
    my $self = shift;
    $self->type_lines('diff -u ' . join ' ', @_);
    $self->run_quiet('diff -u --color', @_, '|| true');
    $self->nl_prompt;
}

# Pipe command output to yq.
sub type_run_yq {
    my $self = shift;
    $self->type_lines(@_);
    run _env join ' ', @_;
    _yq capture _env join ' ', @_;
}


# Decode the contents of a file into JSON and return the resulting Perl value.
sub decode_json_file {
    my $self = shift;
    my $path = _env shift;
    open my $fh, '<:raw', $path or die "Cannot open $path: $!\n";
    return decode_json join '', <$fh>;
}

=head3 handle

Handles an HTTP request, printing out the response body. Returns the decoded
response if its type is JSON; otherwise returns C<undef>.

=cut

sub handle {
    my ($self, $res, $expect_status, $quiet) = @_;
    die  $res->code . ': ' . $res->message . "\n\n" . $res->decoded_content . "\n"
        unless $res->code == $expect_status;

    my $head = $res->headers;
    unless ($quiet) {
        say $res->protocol, " ", $res->code;
        if (my $loc = $head->header('location')) {
            say "Location: $loc";
        }
    }

    my $body = $res->{content};
    my $ret;
    if ($head->content_length && $head->content_type =~ m{^application/json\b}) {
        $ret = decode_json $res->content;
        return $ret if $quiet;
        _yq $body;
        $self->nl_prompt;
    } elsif (!$quiet) {
        say $res->decoded_content if $head->content_length;
        $self->nl_prompt;
    }
    return $ret;
}

sub request {
    my ($self, $method, $url, $body) = @_;
    my $req = HTTP::Request->new($method, $url, $self->{head});
    $req->add_content_utf8($body)
    $self->{curl}->request($req);
}

sub get_quiet {
    my ($self, $path, $expect_status) = @_;
    my $url = URI->new($self->{base_url} . _env $path);
    $self->handle(
        $self->request(GET => $url),
        $expect_status || 200, # OK
        1,
    );
}

sub get {
    my ($self, $path, $expect_status) = @_;
    my $url = $self->_type_url('GET', $path);
    say $url;
    $self->handle(
        $self->request(GET => $url),
        $expect_status || 200, # OK
    );
}

sub del {
    my ($self, $path, $expect_status) = @_;
    my $url = $self->_type_url('DELETE', $path);
    $self->handle(
        $self->request(DELETE => $url),
        $expect_status || 204, # NO CONTENT
    );
}

sub post {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('POST', $path, $data);
    $self->handle(
        $self->request(POST => $url),
        $expect_status || 201, # NO CONTENT
    );
}

sub put {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('PUT', $path, $data);
    $self->handle(
        $self->request(PUT => $url),
        $expect_status || 200, # OK
    );
}

sub patch {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('PATCH', $path, $data);
    $self->handle(
        $self->request(PUT => $url),
        $expect_status || 200, # OK
    );
}

sub query {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('QUERY', $path, $data);
    $self->handle(
        $self->request(QUERY => $url),
        $expect_status || 200, # OK
    );
}

sub _type_url {
    my ($self, $method, $path, $data) = @_;
    $self->type($method, "\$URL/$path", (defined $data ? ($data) : ()));
    return URI->new($self->{base_url} . _env $path);
}

=head3 C<tail_log>

Prints the last four lines of the log from the Docker container passed to it,
then displays a prompt.

=cut

sub tail_log {
    my ($self, $container, $num_lines) = @_;
    $num_lines ||= 4;
    $self->type_run("docker logs -n $num_lines $container");
    $self->nl_prompt;
}
