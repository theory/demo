#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use HTTP::Status qw(:constants);
use Test::More 'no_plan';
use Test::MockModule;
use Test::File::Contents;
use Test::Exception;
use Test::NoWarnings qw(had_no_warnings);

BEGIN {
    delete $ENV{PERSON};
    delete $ENV{FELINE};
    $ENV{TMPDIR} =~ s/\/+\z// if $ENV{TMPDIR};
    $ENV{TERM} = "vt100";

    use_ok 'Theory::Demo' or die
}

# Use -1 for input. This causes Term::TermKey to create a an instance without
# a file handle, and we can push bytes onto it.
my $input = -1;

# Setup output file handle to capture output in the $out scalar.
open my $output, '>:utf8', \my $out or die "Cannot open output to scalar: $!";

sub reset_output {
    $out = '';
    $output->seek(0, 0);
}

##############################################################################
# Test just input param.
ok my $demo = Theory::Demo->new(input => $input),
     'Should create demo with just input param';
is_deeply $demo->{curl}, WWW::Curl::Simple->new, 'Should have curl client';
is_deeply $demo->{head}, HTTP::Headers->new, 'Should have empty headers';
is_deeply $demo->{headers}, ['Location'], 'Should have default emit headers';
isa_ok $demo->{tk}, 'Term::TermKey';
is $demo->{prompt}, 'demo', 'Should have default prompt';
is $demo->{out}, \*STDOUT, 'Should point to STDOUT';
is_deeply $demo->{env}, {%ENV}, 'Should have copied %ENV';

# Test all params.
$ENV{TMPDIR} = '/tmp/';
$ENV{HARPO_TEST_VAL} = 'gargantuan';
ok $demo = Theory::Demo->new(
    prompt    => 'bagel',
    base_url  => 'https://hi/',
    ca_bundle => 'foo',
    user      => 'peggy',
    input     => $input,
    output    => $output,
    headers   => [qw(Location Link)],
), 'Should create demo with all params';

is_deeply $demo->{curl}, WWW::Curl::Simple->new(
    check_ssl_certs => 1,
    ssl_cert_bundle => 'foo',
), 'Should have configured curl client';

my $head = HTTP::Headers->new;
$head->authorization_basic('peggy');
is_deeply $head, $demo->{head}, , 'Should have configured headers';
is_deeply $demo->{headers}, [qw(Location Link)], 'Should have passed headers';
isa_ok $demo->{tk}, 'Term::TermKey';
is $demo->{prompt}, 'bagel', 'Should have specified prompt';
is $demo->{out}, $output, 'Should point to output file handle';
is_deeply $demo->{env}, {%ENV, TMPDIR => '/tmp'},
    'Should have copied %ENV and stripped the trailing slash from TMPDIR';

##############################################################################
# Test b58_uuid.
is $demo->b58_uuid('NpAkRPsPPhzrRWWKPJgi5V'),
    'b0a5e079-b36a-47be-924b-367e4a230bb0',
    'Should parse UUID from NpAkRPsPPhzrRWWKPJgi5V';
is $demo->b58_uuid('LfkWo9c7pu2Nkn9HQgMgfF'),
    '9f46b6ce-0b70-437c-9055-8ea65a488216',
    'Should parse UUID from LfkWo9c7pu2Nkn9HQgMgfF';

# Test b58_int
is $demo->b58_int('1111111j'), Math::BigInt->new(42),
    "Should parse 42 from 1111111j";
is $demo->b58_int('11114GmR58'), Math::BigInt->new(2147483647),
    "Should parse max int32 from 11114GmR58";
is $demo->b58_int('jpXCZedGfVQ'), Math::BigInt->new(18446744073709551615),
    "Should parse max uint64 from jpXCZedGfVQ";
is $demo->b58_int('11111111'), Math::BigInt->new(0),
    "Should parse 0 from 11111111";

##############################################################################
# Test bold
is Term::ANSIColor::colored([qw(bold bright_yellow)], "hi", "there"),
    $demo->bold("hi", "there"), "Should get bold bright yellow from bold()";
is Term::ANSIColor::colored([qw(bold bright_yellow)], "😀➡︎Ã"),
    $demo->bold("😀➡︎Ã"), "Should get bold bright yellow from bold(unicode)";

# Test emit.
my @lorum = (
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do ",
    "eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut ",
    "enim ad minim veniam, quis nostrud exercitation ullamco laboris ",
    "nisi ut aliquip ex ea commodo consequat.",
);

for my $lines (
    ["one line", "this is the start of something new."],
    ["two words", "this", "that"],
    \@lorum,
    ["Emoji", "⌚➡️ 🥶 😞 😔."],
) {
    reset_output;
    my $desc = shift @{ $lines };
    $demo->emit(@{ $lines });
    is $out, encode_utf8 join('', @{ $lines }), "Should have emit $desc";
}

# Test prompt.
my $gt = "\xe2\x9d\xaf";
reset_output;
$demo->prompt;
is $out, "bagel $gt ", 'Should have output prompt';
$demo->nl_prompt;
is $out, "bagel $gt \nbagel $gt ",
    'Should have output newline and prompt';

##############################################################################
# Test wait_for_enter.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b 8 9 Enter));
$demo->wait_for_enter;
is $out, "\n", 'Should have newline after enter';

# Test wait_for_escape.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b 8 9 Escape));
$demo->wait_for_escape;
is $out, "\n", 'Should have newline after escape';

# Test type.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b c Enter));
$demo->type('now');
is $out, "now\n", 'Should have typed "now"';

# Test type with emoji.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b c d Enter));
$demo->type('go ⏰');
is $out, encode_utf8("go ⏰\n"), 'Should have typed with emoji';

# Test Enter to type to the end of a string.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b c Enter Enter));
$demo->type(qw(now is the time));
is $out, "now is the time\n", 'Should have typed "now is the time"';

# Test Enter to type up to a newline.
reset_output;
$demo->{tk} = MockTermKey->new(qw(a b c Enter Enter Enter));
$demo->type("now is the time\n", 'to drink coffee');
is $out, "now is the time\n to drink coffee\n",
    'Should have typed both lines';

# Test type with escapes.
reset_output;
my $msg = 'It’s ' . $demo->bold('clobberin’');
$demo->{tk} = MockTermKey->new(('x') x (1 + length $msg), 'Enter');
$demo->type($msg);
is $out, encode_utf8("$msg\n"), 'Should have typed with trailing ANSI escape';

reset_output;
$msg = 'It’s ' . $demo->bold('clobberin’') . ' time';
$demo->{tk} = MockTermKey->new(('x') x (1 + length $msg), 'Enter', 'Enter');
$demo->type($msg);
is $out, encode_utf8("$msg\n"), 'Should have typed with middle ANSI escape';

reset_output;
$msg = 'It’s ' . $demo->bold('');
$demo->{tk} = MockTermKey->new(('x') x (1 + length $msg), 'Enter');
$demo->type($msg);
is $out, encode_utf8("$msg\n"), 'Should have typed with empty ANSI escape';

# Mock the type() method from here on.
my $module = Test::MockModule->new('Theory::Demo');
$module->mock(type => sub { shift->emit(@_, "\n") });
reset_output;
$demo->type('howdy');
is_deeply $out, "howdy\n", 'Should have swizzled type()';

# Test echo.
reset_output;
$demo->echo("I like corn\n", "Like a lot");
is $out, "I like corn\nLike a lot\nbagel $gt ", 'Should have echoed output';

# Test comment.
reset_output;
$demo->comment("I like corn\nLike a lot\n", "You too?");
my $exp = $demo->bold("# I like corn\n# Like a lot\n# You too?");
is $out, "$exp\nbagel $gt ", 'Should have emitted comment';

##############################################################################
# Mock the IPC::System::Simple functions.
my $ipc = MockSystem->new;
$module->mock(run => sub { $ipc->run(@_) });
$module->mock(runx => sub { $ipc->runx(@_) });
$module->mock(capture => sub { $ipc->capture(@_) });
$module->mock(capturex => sub { $ipc->capturex(@_) });

# Test start.
reset_output;
$demo->start;
is_deeply $ipc->args, {runx => [['clear']]}, 'Should have run clear';
is $out, "bagel $gt ", 'Should have output prompt';

reset_output;
$ipc->setup;
$demo->start('howdy');
$msg = $demo->bold('# howdy');
is_deeply $ipc->args, {runx => [['clear']]}, 'Should have run clear';
is $out, "bagel $gt $msg\nbagel $gt ", 'Should have output prompt and comment';

# Test clear.
reset_output;
$ipc->setup;
$demo->clear;
is_deeply $ipc->args, {runx => [['clear']]}, 'Should have run clear';
is $out, "clear\nbagel $gt ", 'Should have output clear and prompt';

# Test clear_now.
reset_output;
$ipc->setup;
$demo->clear_now;
is_deeply $ipc->args, {runx => [['clear']]}, 'Should have run clear';
is $out, "bagel $gt ", 'Should have output just the prompt';

##############################################################################
# Test setenv and env.
delete $ENV{TMPDIR};
for (my ($k, $v) = each %ENV) {
    is $demo->_env("foo \$$k bar"), "foo $v bar", "_env should replace \$$k";
}

# Test with unknown variables.
is $demo->_env("foo \$PERSON bar"), "foo PERSON bar",
    "_env should replace \$PERSON with the variable name";
is $demo->_env("foo \$FELINE bar"), "foo FELINE bar",
    "_env should replace \$FELINE with the variable name";

# Test with no arg.
is $demo->_env(undef), undef, 'Should get undef for undef arg to _env';
is $demo->_env(""), "", 'Should get "" for "" arg to _env';

# Add more variables.
$demo->setenv(PERSON => 'theory');
$demo->setenv(FELINE => 'bagel');
is $demo->_env("foo \$PERSON bar"), "foo theory bar",
    "_env should replace \$PERSON with the variable value";
is $demo->_env("foo \$FELINE bar"), "foo bagel bar",
    "_env should replace \$FELINE with the variable value";

##############################################################################
# Test grab.
reset_output;
$ipc->setup(capturex_returns => ["some output\n"]);
is $demo->grab(qw(ls -lah)), 'some output', 'Should have chomped output';
is_deeply $ipc->args, {capturex => [[qw(ls -lah)]]},
    'Should have executed command';

reset_output;
$ipc->setup(capturex_returns => ["some output\nand more output\n"]);
is $demo->grab(qw(ls -ahl)), "some output\nand more output",
    'Should have chomped multiline output';
is_deeply $ipc->args, {capturex => [[qw(ls -ahl)]]},
    'Should have executed command';

##############################################################################
# Test type_lines.
reset_output;
$demo->type_lines($lorum[0]);
is $out, "$lorum[0]\n", 'Should have typed single line';

reset_output;
$demo->type_lines(@lorum);
is $out, join(" \\\n", @lorum) . "\n", 'Should have typed multiple lines';

# Test type_run.
reset_output;
$ipc->setup;
$demo->type_run($lorum[0]);
is $out, "$lorum[0]\n", 'Should have typed single line';
is_deeply $ipc->args, { run => [[$lorum[0]]]},
    'Should have executed single line';

reset_output;
$ipc->setup;
$demo->type_run(@lorum);
is $out, join(" \\\n", @lorum) . "\n", 'Should have typed multiple lines';
is_deeply $ipc->args, { run => [[join ' ' => @lorum]]},
    'Should have executed multiple lines';

# Test run_quiet.
reset_output;
$ipc->setup;
$demo->run_quiet(@lorum);
is $out, '', 'Should have no output';
is_deeply $ipc->args, { run => [[join ' ' => @lorum]]},
    'Should have executed multiple lines';

# Test type_run_clean.
reset_output;
$ipc->setup(capture_returns => ["this is /tmp/foo/bar/baz lol\n"]);
$demo->{env}{TMPDIR} = '/tmp/foo/bar';
$demo->type_run_clean("ls -lah");
is $out, "ls -lah\nthis is /tmp/baz lol\n",
    'Should have typed command and cleaned output';
is_deeply $ipc->args, { capture => [["ls -lah"]]},
    'Should have passed command to capture';

# Test with no TMPDIR.
reset_output;
delete $demo->{env}{TMPDIR};
$ipc->setup;
$demo->type_run_clean("ls -lah");
is $out, "ls -lah\n",
    'Should have typed command and uncleaned output';
is_deeply $ipc->args, { run => [["ls -lah"]]},
    'Should have passed command to run';

##############################################################################
# Test _yq.
reset_output;
$ipc->setup(runx_callback => sub {
    my $fn = pop @{ $_[0] };
    file_contents_eq $fn, 'some YAML', 'Should have written YAML to temp file';
});
Theory::Demo::_yq("some YAML");
is_deeply $ipc->args, {runx => [[qw(yq -oj)]]}, 'Should have called yq';

# Test yq.
reset_output;
$ipc->setup;
$demo->yq("some_file.yaml");
is $out, "yq -oj . some_file.yaml\n\nbagel $gt ",
    'Should have typed yq command and then the prompt';
is_deeply $ipc->args, { run => [["yq -oj . some_file.yaml"]]},
    'Should have executed yq on the file';

reset_output;
$ipc->setup;
$demo->yq("some_file.yaml", ".body.profile");
is $out, "yq -oj .body.profile some_file.yaml\n\nbagel $gt ",
    'Should have typed yq command with path and then the prompt';
is_deeply $ipc->args, { run => [["yq -oj .body.profile some_file.yaml"]]},
    'Should have executed yq with the path on the file';

# Test type_run_yq.
reset_output;
$ipc->setup(
    capture_returns => ["name: theory\ncat: bagel"],
    runx_callback => sub {
        my $fn = pop @{ $_[0] };
        file_contents_eq $fn, "name: theory\ncat: bagel",
            'Should have written YAML to temp file';
    },
);
$demo->type_run_yq('cat file.yaml');
is_deeply $ipc->args, {
    runx => [[qw(yq -oj)]],
    capture => [['cat file.yaml']]
}, 'Should have captured the command and called yq';
is $out, "cat file.yaml\n", 'Should have echoed command then prompt';

##############################################################################
# Test diff.
reset_output;
$ipc->setup;
$demo->diff("file1.text", "file2.text");
is_deeply $ipc->args, {
    run => [["diff -u --color file1.text file2.text || true"]],
}, 'Should run the files through diff';
is $out, "diff -u file1.text file2.text\n\nbagel $gt ",
    'Should have typed diff command then prompt';

##############################################################################
# Test decode_json_file.
reset_output;
my $json_file = 't/resource.json';
is_deeply $demo->decode_json_file($json_file), {
  identifier => Math::BigInt->new("113059749145936325402354257176981405696"),
  number     => 9999,
  active     => JSON::PP::true,
  username   => "chrissy",
  name       => "Chrisjen Avasarala",
  emoji      => "🥻",
}, 'Should have read JSON from file';

# Test decode_json_file failure.
reset_output;
throws_ok { $demo->decode_json_file('nonesuch.json') }
    qr/^Cannot open nonesuch.json: /,
    'Should get an error for nonexistent file.';

##############################################################################
# Test type_run_psql with a short query.
reset_output;
$ipc->setup;
$demo->type_run_psql("SELECT COUNT(*) FROM users");
is $out, qq{psql -tXxc "SELECT COUNT(*) FROM users"\n\nbagel $gt },
    'Should have one-line query output';
is_deeply $ipc->args, {
    run => [[qq{psql -tXxc "SELECT COUNT(*) FROM users"}]],
}, 'Should have run the psql command';

# Test with a single long line.
reset_output;
$ipc->setup;
my $sql = q{    SELECT COUNT(*) FROM public.users WHERE name LIKE 'Smith%' AND status = 'active'};
$demo->type_run_psql($sql);
is $out, qq{psql -tXxc "\n$sql\n"\n\nbagel $gt },
    'Should have long query on own line';
is_deeply $ipc->args, {
    run => [[qq{psql -tXxc "$sql"}]],
}, 'Should have run the psql command';

# Test with multiple lines.
reset_output;
$ipc->setup;
my @sql = (
    q{    SELECT COUNT(*) FROM public.users},
    q{    WHERE  name LIKE 'Smith%'},
    q{    AND    status = 'active'},
);
$demo->type_run_psql(@sql);
is $out, qq{psql -tXxc "\n} . join("\n", @sql) . qq{\n"\n\nbagel $gt },
    'Should have query on multiple lines';
is_deeply $ipc->args, {
    run => [[qq{psql -tXxc "} . join(' ', @sql) . qq{"}]],
}, 'Should have run the multiline psql command';

##############################################################################
# Mock Curl and Test request method.
my $curl = MockCurl->new(response => HTTP::Response->new(HTTP_OK, 'OK'));
$demo->{curl} = $curl;

# Test GET request.
ok my $res = $demo->request("GET", "/widgets"), 'Make request';
is_deeply $res, HTTP::Response->new(HTTP_OK, 'OK'), 'Should have 200 response';
is_deeply $curl->{requested},
    [[HTTP::Request->new("GET", "/widgets", $demo->{head})]],
    'Should have made the expected request';

# Test POST request with body.
$curl->setup(response => HTTP::Response->new(HTTP_CREATED, 'Created'));
ok $res = $demo->request("POST", "/widgets", 'some body'),
    'Make POST request';
is_deeply $res, HTTP::Response->new(HTTP_CREATED, 'Created'),
    'Should have 201 response';
is_deeply $curl->{requested},
    [[HTTP::Request->new("POST", "/widgets", $demo->{head}, 'some body')]],
    'Should have made the expected request';

##############################################################################
# Test handle().
sub make_response {
    my ($code, $head, $body) = @_;
    my $msg = HTTP::Status::status_message($code);
    my $res = HTTP::Response->new($code, $msg, $head, $body);
    $res->header('Content-Length' => length $body);
    $res->protocol('HTTP/2');
    return $res;
}

reset_output;
my $response = make_response(HTTP_OK, undef, '{"id": 42}');
is $demo->handle($response, HTTP_OK), undef,
    'Should get undef for simple response';
is $out, qq{HTTP/2 200\n\n{"id": 42}\nbagel $gt }, 'Should have output';

# Unexpected code.
throws_ok { $demo->handle($response, HTTP_CREATED) }
    qr/Expected 201 but got 200: OK\n\n\{"id": 42\}/,
    'Should get exception for unexpected status code';

# Print headers.
reset_output;
$demo->{headers} = [qw(Location Link)];
$head = [
    Location => '/foo/bar',
    Link     => 'This is a link',
    Creation => 'Now',
];

$response = make_response(HTTP_OK, $head, '{"id": 42}');
is $demo->handle($response, HTTP_OK), undef,
    'Should get undef for simple response';
is $out,
    qq{HTTP/2 200\nLocation: /foo/bar\nLink: This is a link\n\n{"id": 42}\nbagel $gt },
    'Should have two desired headers in output';

# Plain text quiet.
reset_output;
$response = make_response(HTTP_OK, $head, '{"id": 42}');
is $demo->handle($response, HTTP_OK, 1), undef,
    'Should get undef for simple response';
is $out, '', 'Should have no output';

# No content.
reset_output;
$response = make_response(HTTP_NO_CONTENT, $head);
is $demo->handle($response, HTTP_NO_CONTENT), undef,
    'Should get undef for simple response';
is $out,
    qq{HTTP/2 204\nLocation: /foo/bar\nLink: This is a link\n\nbagel $gt },
    'Should have no body when no body';

# JSON output.
reset_output;
push @{ $head }, 'Content-Type', 'application/json';
$response = make_response(HTTP_OK, $head, '{"id": 42}');
$module->mock(_yq => sub { $demo->emit("<yq>$_[0]</yq>\n")});
my $json = qq{<yq>{"id": 42}</yq>\n};
is_deeply $demo->handle($response, HTTP_OK), {id => 42},
    'Should get decoded JSON response';
is $out,
    qq{HTTP/2 200\nLocation: /foo/bar\nLink: This is a link\n\n$json\nbagel $gt },
    'Should have _yq-formatted JSON';

# JSON quiet.
reset_output;
is_deeply $demo->handle($response, HTTP_OK, 1), {id => 42},
    'Should get decoded JSON response';
is $out, '', 'Should have no output';

##############################################################################
# Test _data.
is Theory::Demo::_data "It’s 😀", encode_utf8
    "It’s 😀", '_data should encode data';

is Theory::Demo::_data "\@$json_file", do {
    open my $fh, '<:raw', $json_file or die "Cannot open $json_file: $!";
    join '', <$fh>
}, '_data should encode data';

throws_ok { Theory::Demo::_data '@nonesuch.json' }
    qr/Cannot open nonesuch\.json: /,
    'Should get error from _data for nonexistent file';

##############################################################################
# Mock handle.
my @handle_args;
my $handle_ret;
$module->mock(handle => sub { shift; @handle_args = @_; $handle_ret });

##############################################################################
# Test get.
reset_output;
$res = HTTP::Response->new(HTTP_OK, 'OK', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->get("/some/path"), undef, 'Should get undef from get';
is_deeply \@handle_args, [
    $demo->request(GET => $demo->_url("/some/path")), HTTP_OK,
], 'Should have passed request and default code to handle';
is $out, "GET https://hi//some/path\n", 'Should have output the GET request';

# Test get with status code.
reset_output;
$res = HTTP::Response->new(HTTP_ACCEPTED, 'ACCEPTED', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->get("/some/path", HTTP_ACCEPTED), undef, 'Should get undef from get';
is_deeply \@handle_args, [
    $demo->request(GET => $demo->_url("/some/path")), HTTP_ACCEPTED,
], 'Should have passed request and code to handle';
is $out, "GET https://hi//some/path\n", 'Should have output the GET request';

# Test get_quiet
reset_output;
$res = HTTP::Response->new(HTTP_OK, 'OK', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->get_quiet("/some/path"), undef, 'Should get undef from get_quiet';
is_deeply \@handle_args, [
    $demo->request(GET => $demo->_url("/some/path")), HTTP_OK, 1,
], 'Should have passed request and default code to handle';
is $out, "", 'Should not have output the GET request';

# Test get_quiet with status code.
reset_output;
$res = HTTP::Response->new(HTTP_ACCEPTED, 'ACCEPTED', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->get_quiet("/some/path", HTTP_ACCEPTED), undef,
    'Should get undef from get_quiet';
is_deeply \@handle_args, [
    $demo->request(GET => $demo->_url("/some/path")), HTTP_ACCEPTED, 1,
], 'Should have passed request and code to handle';
is $out, "", 'Should have no output the GET request';

##############################################################################
# Test del.
reset_output;
$res = HTTP::Response->new(HTTP_NO_CONTENT, 'No Content', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->del("/some/path"), undef, 'Should del undef from del';
is_deeply \@handle_args, [
    $demo->request(DELETE => $demo->_url("/some/path")), HTTP_NO_CONTENT,
], 'Should have passed request and default code to handle';
is $out, "DELETE https://hi//some/path\n", 'Should have output the DELETE request';

# Test del with status code.
reset_output;
$res = HTTP::Response->new(HTTP_OK, 'OK', [], '{"id": 1234}');
$curl->setup(response => $res);
is $demo->del("/some/path", HTTP_OK), undef, 'Should del undef from del';
is_deeply \@handle_args, [
    $demo->request(DELETE => $demo->_url("/some/path")), HTTP_OK,
], 'Should have passed request and code to handle';
is $out, "DELETE https://hi//some/path\n", 'Should have output the DELETE request';

##############################################################################
# Test post, put, patch, and query.
my $path = "/some/path";
my $url = $demo->_url($path);
for my $tc (
    {
        meth => 'post',
        action => 'POST',
        body => '{"id": 1234}',
        code => HTTP_ACCEPTED,
    },
    {
        meth => 'post',
        action => 'POST',
        body => "\@$json_file",
        exp => HTTP_CREATED,
    },
    {
        meth => 'put',
        action => 'PUT',
        body => '{"id": 1234}',
        code => HTTP_ACCEPTED,
    },
    {
        meth => 'put',
        action => 'PUT',
        body => "\@$json_file",
        exp => HTTP_OK,
    },
    {
        meth => 'patch',
        action => 'PATCH',
        body => '{"id": 1234}',
        code => HTTP_ACCEPTED,
    },
    {
        meth => 'patch',
        action => 'PATCH',
        body => "\@$json_file",
        exp => HTTP_OK,
    },
    {
        meth => 'query',
        action => 'QUERY',
        body => '{"id": 1234}',
        code => HTTP_ACCEPTED,
    },
    {
        meth => 'query',
        action => 'QUERY',
        body => "\@$json_file",
        exp => HTTP_OK,
    },
) {
    reset_output;
    my $res = HTTP::Response->new(
        $tc->{code}, HTTP::Status::status_message($tc->{code} || $tc->{exp}),
        [], $tc->{body},
    );
    $curl->setup(response => $res);
    ok my $meth = $demo->can($tc->{meth}), "can($tc->{meth})";
    is $demo->$meth($path, $tc->{body}, $tc->{code}), undef,
        "Should undef from $tc->{meth}";
    my $data = encode_utf8 Theory::Demo::_data($tc->{body});
    is_deeply \@handle_args, [
        $demo->request($tc->{meth}, $url, $data), $tc->{exp} || $tc->{code},
    ], 'Should have passed request and default code to handle';
    is $out, "$tc->{action} $url $data\n",
        "Should have output the $tc->{action} request";
}

##############################################################################
# Test tail_docker_log.
reset_output;
$demo->tail_docker_log('sushi');
is $out, "docker logs -n 4 'sushi'\n\nbagel $gt ",
    'Should have emitted logs -n 4';

reset_output;
$demo->tail_docker_log('👋🏻 howdy', 8);
is $out, "docker logs -n 8 '" . encode_utf8('👋🏻') . " howdy'\n\nbagel $gt ",
    'Should have emitted encoded logs -n 8';

##############################################################################
# Finish up.
had_no_warnings;
done_testing;

MOCKS: {
    package MockTermKey;

    sub new {
        my $pkg = shift;
        return bless { keys => [map { MockKey->new($_) } @_] } => $pkg;
    }

    sub waitkey {
        my $self = shift;
        die "No keys left to return from waitkey" unless @{ $self->{keys} };
        $_[0] = shift @{ $self->{keys} };
    }

    package MockKey;

    sub new {
        my $pkg = shift;
        return bless { format => shift } => $pkg;
    }

    sub format { return $_[0]->{format} }

    package MockSystem;

    sub new {
        my $pkg = shift;
        my $self = bless {} => $pkg;
        $self->setup(@_);
        return $self;
    }

    sub setup {
        my ($self, %p) = @_;
        %{ $self } = (
            run_args         => [],
            run_returns      => [],
            run_errors       => [],

            runx_args        => [],
            runx_returns     => [],
            runx_errors      => [],
            runx_callback    => undef,

            capture_args     => [],
            capture_returns  => [],
            capture_errogs   => [],

            capturex_args    => [],
            capturex_returns => [],
            capturex_errors  => [],
            %p,
        )
    }

    sub args {
        my $self = shift;
        return {
            map { $_ => $self->{$_ . '_args'} }
            grep { @{ $self->{$_ . '_args'} } }
            qw( run runx capture capturex )
        }
    }

    sub run {
        my $self = shift;
        push @{ $self->{run_args} } => \@_;
        if (my $err = shift @{ $self->{run_errors} }) {
            die $err;
        }
        return shift @{ $self->{run_returns} };
    }

    sub runx {
        my $self = shift;
        $self->{runx_callback}->(\@_) if $self->{runx_callback};
        push @{ $self->{runx_args} } => \@_;
        if (my $err = shift @{ $self->{runx_errors} }) {
            die $err;
        }
        return shift @{ $self->{runx_returns} };
    }

    sub capture {
        my $self = shift;
        push @{ $self->{capture_args} } => \@_;
        if (my $err = shift @{ $self->{capture_errors} }) {
            die $err;
        }
        return shift @{ $self->{capture_returns} };
    }

    sub capturex {
        my $self = shift;
        push @{ $self->{capturex_args} } => \@_;
        if (my $err = shift @{ $self->{capturex_errors} }) {
            die $err;
        }
        return shift @{ $self->{capturex_returns} };
    }

    package MockCurl;

    sub new {
        my $pkg = shift;
        my $self = bless {} => $pkg;
        $self->setup(@_);
        return $self;
    }

    sub setup {
        my $self = shift;
        %{ $self } = (
            response => undef,
            requested => [],
            @_
        );
    }

    sub request {
        my $self = shift;
        push @{ $self->{requested} } => \@_;
        return $self->{response};
    }

}