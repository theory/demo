#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;

use Test::More 'no_plan';
BEGIN { use_ok 'Theory::Demo' or die }

my $demo = Theory::Demo->new;
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