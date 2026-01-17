package Theory::Demo;

use v5.28;
use strict;
use warnings;
use utf8;

use Crypt::Misc qw(decode_b58b);
use Encode qw(encode_utf8 decode_utf8);
use File::Temp;
use Getopt::Long;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status qw(HTTP_OK HTTP_CREATED HTTP_NO_CONTENT);
use IPC::System::Simple 1.17 qw(capturex run runx capture);
use JSON::PP ();
use Math::BigInt;
use Term::ANSIColor ();
use String::ShellQuote;
use Term::TermKey;
use URI;
use WWW::Curl::Easy;

our $VERSION = v0.40.0;

my $json = JSON::PP->new->utf8->allow_bignum;

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

=item C<authorization>

String to include in the Authorization header. Request command echoing
includes C<-H $AUTH> if set.

=item C<user>

Username to include in the Authorization header. Ignored if C<authorization>
is set. Request command echoing includes C<-H $AUTH> if set.

=item C<input>

File handle from which to read input. Defaults to C<STDIN>.

=item C<output>

File handle to which to send output. Defaults to C<STDOUT>.

=item C<headers>

List of headers to print when emitting an HTTP response. Defaults to
C<['Location']>.

=item C<clear>

Makes the C<clear> method a no-op when set to false. Defaults to true.

=item C<type_chars>

Boolean indicating that, rather than wait for the enter key to emit an entire
line, emit the line character by character for any key entry until a newline,
then wait for the enter key to go on to the next command. The enter key will
still short-circuit the typing and print the rest of a line.

=item C<content_type>

Content type to include in all HTTP requests. Defaults to no content type.

=back

=cut

sub new {
    my ($pkg, %params) = @_;
    # Configure request headers.
    $params{head} = HTTP::Headers->new;
    if (my $type = delete $params{content_type}) {
        $params{head}->content_type($type);
    }
    if (my $auth = delete $params{authorization}) {
        $params{head}->authorization($auth);
    } elsif (my $u = delete $params{user}) {
        $params{head}->authorization_basic($u);
    }

    # Configure response headers to print.
    $params{headers} ||= ['Location'];

    # Set up input and output file handles.
    $params{tk} = Term::TermKey->new(delete $params{input} || \*STDIN);
    $params{tk}->set_flags(Term::TermKey::FLAG_UTF8);
    $params{out} = delete $params{output} || \*STDOUT;
    $params{out}->autoflush(1);
    $params{out}->binmode(':utf8');

    # Set up environment.
    $params{env} = {%ENV};
    $params{env}->{TMPDIR} =~ s/\/+\z// if $ENV{TMPDIR};
    $params{clear} //= 1;

    # Trim trailing slash from base URL and return the object.
    $params{base_url} =~ s/\/+\z// if $params{base_url};
    return bless { prompt => 'demo', %params } => $pkg;
}

=head2 Methods

=head3 C<authorize>

Set the string to include in the Authorization header. Echos setting the
C<AUTH> environment variable unless a second argument is true. Once
authorized, HTTP requests will echo C<-H $AUTH> as part of the command
output.

=cut

sub authorize {
    my ($self, $auth, $quiet) = @_;
    $self->{head}->authorization($auth);
    $self->setenv(AUTH => "Authorization: $auth") unless $quiet;
}

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
    print { $self->{out} } @_;
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
    return $self->_type_chars(@_) if $self->{type_chars};
    return $self->_type_lines(@_);
}

sub _type_lines {
    my $self = shift;
    my $tk = $self->{tk};
    my $str = join ' ' => @_;
    my $len = length $str;

    for (my $i = 0; $i < $len; $i++) {
        $tk->waitkey(my $k);
        $tk->waitkey($k) while $k->format(0) ne 'Enter';

        # Emit until newline.
        my $c = substr $str, $i, 1;
        while ($c ne "\n" && $i < length $str) {
            $self->emit($c = substr $str, $i++, 1);
        }
        $i--;
    }
    $self->wait_for_enter;
}

sub _type_chars {
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
        while ($c eq "\e") {
            # Print until the escape close character.
            while ($c ne "m") {
                $self->emit($c = substr $str, ++$i, 1);
            }

            # Print the first char after, if there is one.
            $self->emit($c = substr $str, ++$i, 1) if $i < length($str)-1;
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

Clears the screen and emits a prompt unless C<$self->{clear}> is false, and
emits any arguments as comments followed by a prompt.

=cut

sub start {
    my $self = shift;
    if ($self->{clear}) {
        $self->clear_now;
    }
    $self->comment(@_) if @_;
}

=head3 C<clear>

Types "clear" then clears the screen and emits a prompt or dispatches
L<C<nl_prompt>> when C<$self->{clear}> is false.

=cut

sub clear {
    my $self = shift;
    return $self->nl_prompt unless $self->{clear};
    $self->type('clear');
    $self->clear_now;
}

=head3 C<clear_now>

Clears the screen and emits a prompt or dispatches to L<C<nl_prompt>> when
C<$self->{clear}> is false.

=cut

sub clear_now {
    my $self = shift;
    return $self->nl_prompt unless $self->{clear};
    runx 'clear';
    $self->prompt;
}

=head3 C<setenv>

Sets an environment variable to a value, after which the variables can be used
in arguments to the following functions where they will be emitted as a
variable but the variable will be replaced before execution. System variables
are included by default so can just be used. Variables used in the value
passed to C<setenv> will be interpolated.

=over

=item * C<type_run>

=item * C<run_quiet>

=item * C<type_run_clean>

=item * C<type_run_yq>

=item * C<decode_json_file>

=item * C<type_run_psql>

=item * C<get_quiet>

=item * C<post_quiet>

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
    $self->nl_prompt;
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
    $self->nl_prompt;
}

# Runs a JSON object through yq for pretty-printing.
sub _yq {
    my $fh = File::Temp->new(SUFFIX => '.json');
    print {$fh} @_;
    $fh->close;
    runx 'yq', $fh->filename;
}

=head C<yq>

  $demo->yq('some_file.yaml');
  $demo->yq('some_file.yml', ".body.profile");

Selects and output a path from a JSON file using C<yq> for pretty-printing.
Arguments must properly quoted for use in a shell.

=cut

sub yq {
    my ($self, $file, $path) = @_;
    $self->type_run(join ' ', 'yq', ($path ? ($path) : ()), $file);
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

Diffs two files. Requires C<--color>. On macOS, C<brew install diffutils>.
Arguments must properly quoted for use in a shell.

=cut

sub diff {
    my $self = shift;
    $self->type_lines('diff -u ' . join ' ', @_);
    $self->run_quiet('diff -u --color', @_, '|| true');
    $self->nl_prompt;
}

=head C<decode_json_file>

Decodes the contents of a file into JSON and returns the resulting Perl value.
Decodes large numbers into L<Math::BigInt> or L<Math::BigFloat> values, as
appropriate. The file name must be properly quoted for use in a shell.

=cut

sub decode_json_file {
    my $self = shift;
    my $path = $self->_env(shift);
    open my $fh, '<:raw', $path or die "Cannot open $path: $!\n";
    return $json->decode(join '', <$fh>);
}

=head C<type_run_psql>

Emits C<psql -tXxc "$query">, executes it, then calls C<nl_prompt>. The query
may be multiple lines and must not contain double quotes.

Prints a single line if there is only one line passed and it's less than 72
characters long. Otherwise prints the query on multiple lines; consider
indenting each line.

=cut

sub type_run_psql {
    my $self = shift;
    if (@_ == 1 && length $_[0] < 72) {
        $self->type(qq{psql -tXxc "$_[0]"});
    } else {
        $self->type(qq{psql -tXxc << "EOQ"\n    } . join("\n    ", @_) . qq{\nEOQ});
    }
    run $self->_env('psql -tXxc "' . join(' ', @_) . '"');
    $self->nl_prompt;
}

=head C<type_run_psql_yq>

Pipes C<psql -tXc> to C<yq -oj> to format JSON output. The query should return
a single value in order to be properly formatted.

=cut

sub type_run_psql_yq {
    my $self = shift;
    if (@_ == 1 && length $_[0] < 64) {
        $self->type(qq{psql -tXc "$_[0]" | yq -oj});
    } else {
        $self->type(qq{psql -tX << "EOQ" | yq -oj\n    } . join("\n    ", @_) . qq{\nEOQ});
    }
    run $self->_env('psql -tXc "' . join(' ', @_) . '" | yq -oj');
    $self->nl_prompt;
}

=head3 C<b58_uuid>

Decodes a base58-encoded UUID to its canonical string representation.

=cut

sub b58_uuid {
    shift;
    my $bytes = decode_b58b shift;
    use bytes;
    return  join '-',
        map { unpack 'H*', $_ }
        map { substr $bytes, 0, $_, '' }
       ( 4, 2, 2, 2, 6 );
}

=head3 C<b58_int>

Decodes a base58-encoded big-endian integer to a Math::BigInt.

=cut

sub b58_int { Math::BigInt->from_bytes(decode_b58b $_[1]) }

=begin comment

=head3 C<_content_is_json>

# Return true if the HTTP::Headers passed indicates JSON content. Returns true
# if the content type is C<"application/json"> or ends in C<"+json">.

=cut

sub _content_is_json($) {
    my $ct = shift->content_type;
    return $ct eq "application/json" || $ct =~ /[+]json$/;
}

=head3 handle

Handles an HTTP response, printing the protocol and status code, headers
configured by C<new()>, and the response body, followed by a newline and the
prompt. For JSON responses, it passes the response body through C<yq> before
printing it. Emits nothing if C<$quiet> is true. Returns the decoded response
if its type is JSON; otherwise returns C<undef>. Dies if the response code
does not match C<$expect_status>.

=cut

sub handle {
    my ($self, $res, $expect_status, $quiet) = @_;
    die sprintf(
        "Expected %d but got %d: %s\n\n%s\n",
        $expect_status, $res->code, HTTP::Status::status_message($res->code),
        $res->decoded_content,
    ) unless $res->code == $expect_status;

    # Emit the protocol, status code and headers of interest.
    my $head = $res->headers;
    unless ($quiet) {
        $self->emit($res->protocol, " ", $res->code, "\n");
        for my $h (@{ $self->{headers} }) {
            if (my $val = $head->header($h)) {
                $self->emit("$h: $val\n");
            }
        }
        $self->emit("\n");
    }

    # Just prompt and return if there is no content.
    unless ($head->content_length) {
        $self->prompt unless $quiet;
        return
    }

    my $body = $res->decoded_content;
    if (_content_is_json $head) {
        # Print out the JSON content, then decode and return it.
        unless ($quiet) {
            _yq $body;
            $self->nl_prompt;
        }
        return $json->decode($body);
    }

    # Emit the content.
    unless ($quiet) {
        $self->emit($body);
        $self->nl_prompt;
    }

    return
}


=head C<request>

Makes a request for the given method, URL, and optional body and returns an
L<HTTP::Response>. The body should be a Perl string which will be encoded as
UTF-8. The request will contain the list of headers passed to C<new()>.

=cut

sub request {
    my ($self, $method, $url, $body) = @_;
    my ($curl, $head, $content) = $self->_curl($method, $url, $body);
    if (my $code = $curl->perform) {
        die "Request failed: " . $curl->strerror($code) . " ($code)\n";
    }

    # Create and return the response.
    my $res = HTTP::Response->parse(${ $head });
    $res->request(HTTP::Request->new($method, $url, $self->{head}, $body));
    $res->content(${ $content });
    return $res;
}

=begin comment

=head3 C<_curl>

Creates a L<WWW::Curl> object (specifically, C<WWW::Curl::Easy) to request
C<$method>, C<$url>, and C<$body> and configured to write the response to
C<$head> and C<$content>, which must be scalar references.

=cut

sub _curl {
    my ($self, $method, $url, $body) = @_;
    # Setup the request.
    my $curl = WWW::Curl::Easy->new;
    $curl->setopt(CURLOPT_NOPROGRESS, 1);
    $curl->setopt(CURLOPT_USERAGENT, __PACKAGE__ . '/' . __PACKAGE__->VERSION);
    $curl->setopt(CURLOPT_CUSTOMREQUEST, $method);
    $curl->setopt(CURLOPT_URL, $url);

    # Setup headers.
    my $h = $self->{head};
    $curl->setopt(CURLOPT_HTTPHEADER, [map {
        my $n = $_;
        map { "$n: $_" } $h->header($n)
    } $h->header_field_names]);

    # Setup the request body.
    if ($body) {
        open my $read, '<:raw', \$body;
        $curl->setopt(CURLOPT_UPLOAD, 1);
        $curl->setopt(WWW::Curl::Easy::CURLOPT_UPLOAD, 1);
        $curl->setopt(WWW::Curl::Easy::CURLOPT_READDATA, \$read);
    }

    # Setup scalars to which to write the response headers and content.
    my ($head, $content) = ('', '');
    open my $head_fh, ">:raw", \$head;
    $curl->setopt(CURLOPT_WRITEHEADER, $head_fh);
    open my $body_fh, ">:raw", \$content;
    $curl->setopt(CURLOPT_WRITEDATA, $body_fh);

    # Limit to 5 redirects with valid auto-referer header.
    $curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $curl->setopt(CURLOPT_MAXREDIRS, 5);
    $curl->setopt(CURLOPT_AUTOREFERER, 1);

    # Verify cert identification and provide a CA bundle if we have one.
    $curl->setopt(CURLOPT_SSL_VERIFYPEER, 1);
    $curl->setopt(CURLOPT_CAINFO, $self->{ca_bundle}) if $self->{ca_bundle};

    # All set.
    return $curl, \$head, \$content;
}

# Encode the data for a request. If the argument starts with "@", C<_data>
# assumes it's a file path and reads and returns its raw bytes. Otherwise,
# it encodes and returns the argument as UTF-8 bytes.
sub _data($) {
    my $data = shift;
    return $data unless $data;
    return encode_utf8 $data unless $data =~ s/^@//;
    open my $fh, '<:raw', $data or die "Cannot open $data: $!\n";
    local $/ = undef;
    return <$fh>;
}

=head C<get>

Creates and types out a "GET $url" line relative to the C<base_url> passed to
C<new()>, then uses the HTTP client created by C<new()> to make an HTTP C<GET>
request and passes the response and expected status to C<handle>. The expected
status defaults to L<HTTP::Status::HTTP_OK> (C<200>).

=cut

sub get {
    my ($self, $path, $expect_status) = @_;
    $self->_req(GET => $path, $expect_status || HTTP_OK);
}

=head C<get_quiet>

Like L<C<get>> but does not type out the "GET $url" line.

=cut

sub get_quiet {
    my ($self, $path, $expect_status) = @_;
    $self->handle(
        $self->request(GET => $self->_url($path)),
        $expect_status || HTTP_OK,
        1,
    );
}

=head C<del>

Creates and types out a C<DELETE $url> line relative to the C<base_url> passed
to C<new()>, then uses the HTTP client created by C<new()> to make an HTTP
C<GET> request and passes the response and expected status to C<handle>. The
expected status defaults to L<HTTP::Status::HTTP_NO_CONTENT> (C<204>).

=cut

sub del {
    my ($self, $path, $expect_status) = @_;
    $self->_req('DELETE', $path, $expect_status || HTTP_NO_CONTENT);
}

=head C<post>

Creates and types out a C<POST $url> line relative to the C<base_url> passed
to C<new()>, then uses the HTTP client created by C<new()> to make an HTTP
C<POST> request and passes the response and expected status to C<handle>. The
expected status defaults to L<HTTP::Status::HTTP_CREATED> (C<201>).

=cut

sub post {
    my ($self, $path, $data, $expect_status) = @_;
    $self->_req('POST', $path, $expect_status || HTTP_CREATED, $data);
}

=head C<post_quiet>

Like L<C<post>> but does not type out the "post $url" line.

=cut

sub post_quiet {
    my ($self, $path, $data, $expect_status) = @_;
    $self->handle(
        $self->request(POST => $self->_url($path), _data $data),
        $expect_status || HTTP_CREATED,
        1,
    );
}

=head C<put>

Creates and types out a C<PUT $url> line relative to the C<base_url> passed
to C<new()>, then uses the HTTP client created by C<new()> to make an HTTP
C<PUT> request and passes the response and expected status to C<handle>. The
expected status defaults to L<HTTP::Status::HTTP_OK> (C<200>).

=cut

sub put {
    my ($self, $path, $data, $expect_status) = @_;
    $self->_req('PUT', $path, $expect_status || HTTP_OK, $data);
}

=head C<patch>

Creates and types out a C<PATCH $url> line relative to the C<base_url> passed
to C<new()>, then uses the HTTP client created by C<new()> to make an HTTP
C<PATCH> request and passes the response and expected status to C<handle>. The
expected status defaults to L<HTTP::Status::HTTP_OK> (C<200>).

=cut

sub patch {
    my ($self, $path, $data, $expect_status) = @_;
    $self->_req('PATCH', $path, $expect_status || HTTP_OK, $data);
}

=head C<patch>

Creates and types out a C<QUERY $url> line relative to the C<base_url> passed
to C<new()>, then uses the HTTP client created by C<new()> to make an
L<HTTP C<QUERY>|https://datatracker.ietf.org/doc/draft-ietf-httpbis-safe-method-w-body/>
request and passes the response and expected status to C<handle>. The expected
status defaults to L<HTTP::Status::HTTP_OK> (C<200>).

=cut

sub query {
    my ($self, $path, $data, $expect_status) = @_;
    $self->_req('QUERY', $path, $expect_status || HTTP_OK, $data);
}

# Creates and types out a C<$meth $url> line relative to the C<base_url>
# passed to C<new()>, then uses the HTTP client created by C<new()> to make a
# request and passes the response and expected status to C<handle>.
sub _req {
    my ($self, $meth, $path, $expect_status, $data) = @_;
    my $url = $self->_type_url($meth, $path, $data);
    $self->handle($self->request($meth => $url, _data $data), $expect_status);
}

# Creates and returns a L<URI> concatenating the C<base_url> passed to
# C<new()> with C<$path>, replacing environment variables in C<$path>.
sub _url {
    my ($self, $path) = @_;
    return URI->new($self->{base_url} . '/' . $self->_env($path));
}

# Type C<$method $self->{base_url}/$path> followed by `$data` if it's defined.
# Insert C<-H $AUTH> after $method if C<authorization> is set. Then creates
# and returns a L<URI> concatenating the C<base_url> passed to C<new()> with
# C<$path>, replacing environment variables in C<$path>.
sub _type_url {
    my ($self, $method, $path, $data) = @_;
    $self->type(
        $method,
        ($self->{head}->authorization ? ('-H $AUTH') : ()),
        shell_quote("$self->{base_url}/$path"),
        (defined $data ? (shell_quote $data) : ()),
    );
    return $self->_url($path)
}

=head3 C<>

Prints the last C<$num_lines> (defaults to 4) lines of the log from the Docker
C<$container, then displays a prompt. C<$container> must contain no quotation
marks.

=cut

sub tail_docker_log {
    my ($self, $container, $num_lines) = @_;
    $num_lines ||= 4;
    $self->type_run("docker logs -n $num_lines '$container'");
}

1;
