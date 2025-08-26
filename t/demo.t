#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;
use Test::More 'no_plan';

BEGIN { use_ok 'Theory::Demo' or die }
$ENV{TERM} = "vt100";

# Use a pipe to create read and write handles. Cannot use regular file
# handles (like open on a scalar ref) because it hits an assertion failure:
# `perl: uniutil.c:183: unibi_from_term: Assertion `term != NULL' failed.`
# So borrow this technique from Term::TermKey.
# https://metacpan.org/release/PEVANS/Term-TermKey-0.19/source/t/03read.t
pipe( my ( $rd, $wr ) ) or die "Cannot pipe() - $!";

# Test just input param.
ok my $demo = Theory::Demo->new(input => $rd),
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
    input     => $rd,
    output    => $wr,
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
is $demo->{out}, $wr, 'Should point to output file handle';

for my $tc (
    {
        b58 => 'NpAkRPsPPhzrRWWKPJgi5V', 
        uuid => 'b0a5e079-b36a-47be-924b-367e4a230bb0',
    },
    {
        b58 => 'LfkWo9c7pu2Nkn9HQgMgfF',
        uuid => '9f46b6ce-0b70-437c-9055-8ea65a488216',
    },
) {
    is $demo->b58_uuid($tc->{b58}), $tc->{uuid}, $tc->{b58};
}

for my $tc (
    {
        test => '42',
        b58 => '1111111j', 
        int => Math::BigInt->new(42),
    },
    {
        test => 'max_int32',
        b58 => '11114GmR58',
        int => Math::BigInt->new(2147483647),
    },
    {
        test => 'max_uint64',
        b58 => 'jpXCZedGfVQ',
        int => Math::BigInt->new(18446744073709551615),
    },
    {
        test => 'zero',
        b58 => '11111111',
        int => Math::BigInt->new(0),
    },
) {
    is $demo->b58_int($tc->{b58}), $tc->{int}, "Test $tc->{test}";
}

done_testing;
