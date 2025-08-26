#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use Test::More 'no_plan';

BEGIN { use_ok 'Theory::Demo' or die }
$ENV{TERM} = "vt100";

# Use -1 for input. This causes Term::TermKey to create a an instance without
# a file handle, and we can push bytes onto it.
my $input = -1;

# Setup output file handle to capture output in the $out scalar.
open my $output, '>:utf8', \my $out or die "Cannot open output to scalar: $!";

sub reset_output {
    $out = '';
    $output->seek(0, 0);
}

# Test just input param.
ok my $demo = Theory::Demo->new(input => $input),
     'Should create demo with just input param';
is_deeply $demo->{curl}, WWW::Curl::Simple->new, 'Should have curl client';
is_deeply $demo->{head}, HTTP::Headers->new, 'Should have empty headers';
isa_ok $demo->{tk}, 'Term::TermKey';
is $demo->{prompt}, 'demo', 'Should have default prompt';
is $demo->{out}, \*STDOUT, 'Should point to STDOUT';

# Test all params.
ok $demo = Theory::Demo->new(
    prompt    => 'bagel',
    base_url  => 'https://hi/',
    ca_bundle => 'foo',
    user      => 'peggy',
    input     => $input,
    output    => $output,
), 'Should create demo with all params';

is_deeply $demo->{curl}, WWW::Curl::Simple->new(
    check_ssl_certs => 1,
    ssl_cert_bundle => 'foo',
), 'Should have configured curl client';

my $head = HTTP::Headers->new;
$head->authorization_basic('peggy');
is_deeply $head, $demo->{head}, , 'Should have configured headers';
isa_ok $demo->{tk}, 'Term::TermKey';
is $demo->{prompt}, 'bagel', 'Should have specified prompt';
is $demo->{out}, $output, 'Should point to output file handle';

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

# Test bold
is Term::ANSIColor::colored([qw(bold bright_yellow)], "hi", "there"),
    $demo->bold("hi", "there"), "Should get bold bright yellow from bold()";
is Term::ANSIColor::colored([qw(bold bright_yellow)], "😀➡︎Ã"),
    $demo->bold("😀➡︎Ã"), "Should get bold bright yellow from bold(unicode)";

# Test emit.
for my $lines (
    ["one line", "this is the start of something new."],
    ["two words", "this", "that"],
    [
        "Lorum ipsum",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do ",
        "eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut ",
        "enim ad minim veniam, quis nostrud exercitation ullamco laboris ",
        "nisi ut aliquip ex ea commodo consequat.",
    ],
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
is $out, encode_utf8("$msg\n"), 'Should have typed with ';

# Swizzle the type method from here on.
SWIZZLE: {
    no warnings 'redefine';
    *Theory::Demo::type = sub {
        isa_ok my $d = shift, 'Theory::Demo';
        $d->emit(@_);
    }
}

reset_output;
$demo->type('howdy');
is_deeply $out, 'howdy', 'Should have swizzled type()';

# Test echo.
reset_output;
$demo->echo("I like corn\n", "Like a lot\n");
is $out, "I like corn\nLike a lot\nbagel $gt ", 'Should have echoed output';

# Test comment.
reset_output;
$demo->comment("I like corn\nLike a lot\n", "You too?\n");
my $exp = $demo->bold("# I like corn\n# Like a lot\n# You too?\n");
is $out, $exp . "bagel $gt ", 'Should have emitted comment';


done_testing;

{
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
}