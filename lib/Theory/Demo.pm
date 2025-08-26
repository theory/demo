package Theory::Demo;

use v5.28;
use strict;
use warnings;
use utf8;

use Crypt::Misc qw(decode_b58b);
use Encode qw(encode_utf8 decode_utf8);
use File::Temp;
use Getopt::Long;
use IO::Socket::SSL;
use IPC::System::Simple 1.17 qw(capturex run runx capture);
use JSON::PP ();
use Math::BigInt;
use Net::SSLeay;
use Term::ANSIColor ();
use Term::TermKey;
use URI;
use WWW::Curl::Simple;

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

=item C<input>

File handle from which to read input. Defaults to C<STDIN>.

=item C<output>

File handle to which to send output. Defaults to C<STDOUT>.

=back

=cut

sub new {
    my ($pkg, %params) = @_;
    # Set up Curl.
    if ($params{ca_bundle}) {
        $params{curl} = WWW::Curl::Simple->new(
            check_ssl_certs => 1,
            ssl_cert_bundle => delete $params{ca_bundle},
        );
    } else {
        $params{curl} = WWW::Curl::Simple->new;
    }

    # Configure request headers.
    $params{head} = HTTP::Headers->new(
        #'Content-Type'  => 'application/json',
    );
    if (my $u = delete $params{user}) {
        $params{head}->authorization_basic($u);
    }

    # Set up input and output file handles.
    $params{tk} = Term::TermKey->new(delete $params{input} || \*STDIN);
    $params{tk}->set_flags(Term::TermKey::FLAG_UTF8);
    $params{out} = delete $params{output} || \*STDOUT;
    $params{out}->autoflush(1);
    $params{out}->binmode(':utf8');

    # Set up environment.
    $params{env} = {%ENV};
    $params{env}->{TMPDIR} =~ s/\/+\z// if $ENV{TMPDIR};

    # Trim trailing slash from base URL and return the object.
    $params{base_url} =~ s/\/+\z// if $params{base_url};
    return bless { prompt => 'demo', %params } => $pkg;
}

=head2 Methods

=head3 C<bold>

Wraps arguments in ANSI bold, bright yellow formatting.

=cut

sub bold {
    shift;
    Term::ANSIColor::colored([qw(bold bright_yellow)], @_);
}

=head3 C<emit>

Prints values to the output file handle.

=cut

sub emit {
    my $self = shift;
    print { $self ->{out} } @_;
}

=head3 C<prompt>

Emits a prompt.

=cut

sub prompt {
    $_[0]->emit("$_[0]->{prompt} ❯ ");
}

=head3 C<nl_prompt>

Emits a newline and a prompt.

=cut

sub nl_prompt {
    $_[0]->emit("\n$_[0]->{prompt} ❯ ");
}

=head3 C<wait_for_enter>

Waits for the user to hit the enter key, then emit a newline.

=cut

sub wait_for_enter {
    $_[0]->_wait_for('Enter');
}

=head3 C<wait_for_escape>

Waits for the user to hit the escape key, then emit a newline.

=cut

sub wait_for_escape {
    $_[0]->_wait_for('Escape');
}

# Wait for a key with a specific format.
sub _wait_for {
    my ($self, $fmt) = @_;
    my $tk = $self->{tk};
    $tk->waitkey(my $key);
    while ($key->format(0) ne $fmt) {
        $tk->waitkey($key);
    }
    $self->emit("\n");
}

=head3 C<type>

Waits for the user to type any key and emits a single character of the the
arguments passed to it for each key. Unless the user hits the enter key, in
which case it will emit every character up to the next newline, then wait.
Returns when it has emitted all of the characters and hits the enter key.

=cut

sub type {
    my $self = shift;
    my $tk = $self->{tk};
    my $str = join ' ' => @_;

    for (my $i = 0; $i < length $str; $i++) {
        $tk->waitkey(my $k);
        my $c = substr $str, $i, 1;
        $self->emit($c);

        # Check for enter key.
        if ($k->format(0) eq 'Enter') {
            while ($c ne "\n" && $i < length $str) {
                $self->emit($c = substr $str, ++$i, 1);
            }
        }

        # Check for ANSI escape.
        if ($c eq "\e") {
            # Print until the escape close character.
            while ($c ne "m") {
                $self->emit($c = substr $str, ++$i, 1);
            }

            # Print the first char after, if there is one.
            $self->emit(substr $str, ++$i, 1) if $i < length $str;
        }
    }

    $self->wait_for_enter;
}

=head3 C<comment>

Echoes its arguments then displays a prompt.

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

=head3 C<start>

Clears the screen, emits a prompt, and emits any arguments as comments
followed by a prompt.

=cut

sub start {
    my $self = shift;
    $self->clear_now;
    $self->comment(@_) if @_;
}

=head3 C<clear>

Types "clear" then clears the screen and emits a prompt.

=cut

sub clear {
    my $self = shift;
    $self->type('clear');
    $self->clear_now;
}

=head3 C<clear>

Clears the screen and emits a prompt.

=cut

sub clear_now {
    runx 'clear';
    shift->prompt;
}

=head3 C<setenv>

Sets an environment variable to a value, after which the variables can be
used in arguments to the following functions where they will be emitted as a
variable but the variable will be replaced before execution. System variables
are included by default so can just be used. Variables used in the value
passed to C<setenv> will be interpolated.

=over

=item * C<type_run>

=item * C<run_quiet>

=item * C<type_run_clean>

=item * C<type_run_yq>

=item * C<decode_json_file>

=item * C<type_run_psql_query>

=item * C<get_quiet>

=item * C<get>

=item * C<del>

=item * C<post>

=item * C<put>

=item * C<patch>

=item * C<query>

=back

=cut

sub _env {
    my $self = shift;
    $_[0] =~ s/\$(\w+)/$self->{env}{$1} || $1/gerx if $_[0]
}

sub setenv {
    my $self = shift;
    my ($k, $v) = @_;
    $self->{env}{$k} = $self->_env($v);
    $self->echo(qq{$k="$v"});
}

=head3 C<grab>

  my $version = $demo->grab(qw(uname -r));

Grab and return the output of a command.

=cut

sub grab {
    shift;
    my $out = capturex @_;
    chomp $out;
    $out;
}

=head C<type_lines>

Types out a list of lines to be "run", appending a backslash to all but the
last, but without actually running anything. Emulates a multi-line shell
command.

=cut

sub type_lines {
    my $self = shift;
    while (@_ > 1) {
        $self->type(shift(@_) . ' \\');
    }
    $self->type(shift);
}

=head C<type_run>

Types out a multi-line command and then runs it.

=cut

sub type_run {
    my $self = shift;
    $self->type_lines(@_);
    run $self->_env(join ' ', @_);
}

=head C<run_quiet>

Runs a multi-line command without first echoing it.

=cut

sub run_quiet {
    my $self = shift;
    run $self->_env(join ' ', @_);
}

=head C<type_run_clean>

Like type_run, but captures the output of the command and replaces any string
matching C<$TMPDIR> wih F</tmp> before printing it, to avoid displaying a
long, ugly macOS tmpdir name.

=cut

sub type_run_clean {
    my $self = shift;
    return $self->type_run(@_) unless $self->{env}{TMPDIR};
    $self->type_lines(@_);
    $self->emit(
        map { s{\Q$self->{env}{TMPDIR}\E}{/tmp}gr }
        capture $self->_env(join ' ', @_),
    );
}

# Runs a JSON object through yq for pretty-printing.
sub _yq {
    my $fh = File::Temp->new;
    print {$fh} @_;
    $fh->close;
    runx qw(yq -oj), $fh->filename;
}

=head C<yq>

  $demo->yq('some_file.yaml');
  $demo->yq('some_file.yml', ".body.profile");

Selects and output a path from a JSON file using C<yq> for pretty-printing.

=cut

sub yq {
    my ($self, $file, $path) = @_;
    $self->type_run(join ' ', 'yq -oj', ($path // '.'), $file);
    $self->nl_prompt;
}

=head C<type_run_yq>

Types out a multi-line command and then pipes its output to C<yq>.

=cut

sub type_run_yq {
    my $self = shift;
    $self->type_lines(@_);
    _yq capture $self->_env(join ' ', @_);
}

=head C<diff>

Diffs two files. Requires C<--color>. On macOS, `brew install diffutils`.

=cut

sub diff {
    my $self = shift;
    $self->type_lines('diff -u ' . join ' ', @_);
    $self->run_quiet('diff -u --color', @_, '|| true');
    $self->nl_prompt;
}

=head C<decode_json_file>

Decodes the contents of a file into JSON and returns the resulting Perl
value. Decodes large numbers into L<Math::BigInt> or L<Math::BigFloat>
values, as appropriate.

=cut

sub decode_json_file {
    my $self = shift;
    my $path = $self->_env(shift);
    open my $fh, '<:raw', $path or die "Cannot open $path: $!\n";
    return JSON::PP->new->utf8->allow_bignum->decode(join '', <$fh>);
}

=head C<type_run_psql_query>

Emits C<psql -tXxc "$query">, executes it, then calls C<nl_prompt>. The
query may be multiple lines and must not contain double quotes.

Prints a single line if there is only one line passed and it's less than 72
characters long. Otherwise prints the query on multiple lines; consider
indenting each line.

=cut

sub type_run_psql {
    my $self = shift;
    if (@_ == 1 && length $_[0] < 72) {
        $self->type(qq{psql -tXxc "$_[0]"});
    } else {
        $self->type(qq{psql -tXxc "\n} . join("\n", @_) . qq{\n"});
    }
    run $self->_env('psql -tXxc "' . join(' ', @_) . '"');
    $self->nl_prompt;
}

# Decodes a base58-encoded UUID to its canonical string representation.
sub b58_uuid {
    shift;
    my $bytes = decode_b58b shift;
    use bytes;
    return  join '-',
        map { unpack 'H*', $_ }
        map { substr $bytes, 0, $_, '' }
       ( 4, 2, 2, 2, 6 );
}

# Decodes a base58-encoded big-endian uint64 to a Math::BigInt.
sub b58_int { Math::BigInt->from_bytes(decode_b58b $_[1]) }

sub key_prefix {
    '01' . unpack("H8", pack("N1", $_[1]));
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
        $self->emit($res->protocol, " ", $res->code, "\n");
        if (my $loc = $head->header('location')) {
            $self->emit("Location: $loc\n");
        }
    }

    my $body = $res->decoded_content;
    my $ret;
    if ($head->content_length && $head->content_type =~ m{^application/json\b}) {
        $ret = decode_json $body;
        return $ret if $quiet;
        _yq $body;
        $self->nl_prompt;
    } elsif (!$quiet) {
        $self->emit($body) if $head->content_length;
        $self->nl_prompt;
    }
    return $ret;
}

sub request {
    my ($self, $method, $url, $body) = @_;
    my $req = HTTP::Request->new($method, $url, $self->{head});
    $req->add_content_utf8($body);
    $self->{curl}->request($req);
}

sub _data($) {
    my $data = shift;
    return encode_utf8 $data unless $data =~ s/^@//;
    open my $fh, '<:raw', $data or die "Cannot open $data: $!\n";
    return join '', <$fh>;
}

sub get_quiet {
    my ($self, $path, $expect_status) = @_;
    my $url = URI->new($self->{base_url} . '/' . $self->_env($path));
    $self->handle(
        $self->request(GET => $url),
        $expect_status || 200, # OK
        1,
    );
}

sub get {
    my ($self, $path, $expect_status) = @_;
    my $url = $self->_type_url('GET', $path);
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
        $self->request(POST => $url, _data $data),
        $expect_status || 201, # NO CONTENT
    );
}

sub put {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('PUT', $path, $data);
    $self->handle(
        $self->request(PUT => $url, _data $data),
        $expect_status || 200, # OK
    );
}

sub patch {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('PATCH', $path, $data);
    $self->handle(
        $self->request(PUT => $url, _data $data),
        $expect_status || 200, # OK
    );
}

sub query {
    my ($self, $path, $data, $expect_status) = @_;
    my $url = $self->_type_url('QUERY', $path, $data);
    $self->handle(
        $self->request(QUERY => $url, _data $data),
        $expect_status || 200, # OK
    );
}

sub _type_url {
    my ($self, $method, $path, $data) = @_;
    $self->type(
        $method, "$self->{base_url}/$path",
        (defined $data ? ($data) : ()),
    );
    return URI->new($self->{base_url} . '/' . $self->_env($path));
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

1;
