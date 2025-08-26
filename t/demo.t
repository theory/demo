#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use Test::More 'no_plan';

BEGIN { use_ok 'Theory::Demo' or die }
$ENV{TERM} = "vt100";

# Use a pipe to create read and write handles. Cannot use regular file
# handles (like open on a scalar ref) because it hits an assertion failure:
# `perl: uniutil.c:183: unibi_from_term: Assertion `term != NULL' failed.`
# So borrow this technique from Term::TermKey.
# https://metacpan.org/release/PEVANS/Term-TermKey-0.19/source/t/03read.t
pipe( my ( $input, $pipe ) ) or die "Cannot pipe() - $!";

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
reset_output;
$demo->prompt;
is $out, encode_utf8 "bagel ❯ ", 'Should have output prompt';
$demo->nl_prompt;
is $out, encode_utf8 "bagel ❯ \nbagel ❯ ",
    'Should have output newline and prompt';

done_testing;
