#!/usr/bin/perl -w

use v5.28;
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use HTTP::Status qw(:constants status_message);
use JSON::PP;
use MIME::Base64;
use Test::More;
use Test::NoWarnings qw(had_no_warnings);
use Theory::Demo;

BEGIN { $ENV{TERM} = "vt100" }

isa_ok my $demo = Theory::Demo->new(
    input    => -1,
    user     => 'theory',
    base_url => $ENV{HTTPBIN_URL} || 'https://httpbingo.org/',
), 'Theory::Demo';

my $base_head = HTTP::Headers->new;
$base_head->authorization_basic('theory');
$base_head->user_agent("Theory::Demo/" . Theory::Demo->VERSION);

for my $tc (
    {
        test => "GET request",
        meth => 'GET',
        path => 'get',
        code => HTTP_OK,
        head => $base_head,
    },
    {
        test => "POST request",
        meth => 'POST',
        path => 'post',
        head => $base_head,
        body => '{"id": 42, "icon": "🥑"}',
    },
    {
        test => "PUT request",
        meth => 'PUT',
        path => 'put',
        head => $base_head,
        body => '{"id": 42, "icon": "🥑"}',
    },
    {
        test => "PATCH request",
        meth => 'PATCH',
        path => 'patch',
        head => $base_head,
        body => '{"id": 42, "icon": "🥑"}',
    },
    {
        test => "DELETE request",
        meth => 'DELETE',
        path => 'delete',
        head => $base_head,
    },
    {
        test => "QUERY request",
        meth => 'QUERY',
        path => 'anything',
        head => $base_head,
        body => '{"id": 42, "icon": "🥑"}',
    },
) {
    subtest $tc->{test} => sub {
        my $req_body = $tc->{body} ? encode_utf8 $tc->{body} : undef;
        ok my $res = $demo->request(
            $tc->{meth} => $demo->_url($tc->{path}),
            $req_body,
        ), $tc->{test};
        ok +(grep { $res->code == $_ } (100, 200)),
            "$tc->{test} should have status 100 or 200";
        ok my $body = decode_json($res->decoded_content), "$tc->{test} decode JSON body";
        is $body->{method}, $tc->{meth}, "$tc->{test} should have sent $tc->{meth} request";
        ok my $head = $body->{headers}, "$tc->{test} should have sent headers";
        for my $hn ($tc->{head}->header_field_names) {
            is_deeply $head->{$hn}, [$tc->{head}->header($hn)],
                "$tc->{test} should have sent $hn header";
        }
        if ($req_body) {
            my $exp = 'data:application/octet-stream;base64,' . encode_base64 $req_body, '';
            is $body->{data}, $exp, "$tc->{test} should have submitted body";
        }
    }
}

had_no_warnings;
done_testing;
