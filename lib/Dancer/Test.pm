package Dancer::Test;

# test helpers for Dancer apps

use strict;
use warnings;
use Test::More import => ['!pass'];

use Carp;
use HTTP::Headers;
use Dancer ':syntax';
use Dancer::App;
use Dancer::Deprecation;
use Dancer::Request;
use Dancer::SharedData;
use Dancer::Renderer;
use Dancer::Config;
use Dancer::FileUtils qw(open_file);

use base 'Exporter';
use vars '@EXPORT';

@EXPORT = qw(
  route_exists
  route_doesnt_exist

  response_exists
  response_doesnt_exist

  response_status_is
  response_status_isnt

  response_content_is
  response_content_isnt
  response_content_is_deeply
  response_content_like
  response_content_unlike
  response_is_file
  response_headers_are_deeply

  dancer_response
  get_response
);

sub import {
    my ($class, %options) = @_;
    $options{appdir} ||= '.';

    # mimic PSGI env
    $ENV{SERVERNAME}        = 'localhost';
    $ENV{HTTP_HOST}         = 'localhost';
    $ENV{SERVER_PORT}       = 80;
    $ENV{'psgi.url_scheme'} = 'http';

    my ($package, $script) = caller;
    $class->export_to_level(1, $class, @EXPORT);

    Dancer::_init_script_dir($options{appdir});
    Dancer::Config->load;

    # set a default session engine for tests
    setting 'session' => 'simple';
    setting 'logger'  => 'Null';
}

# Route Registry

sub route_exists {
    my ($req, $test_name) = @_;

    my ($method, $path) = @$req;
    $test_name ||= "a route exists for $method $path";

    $req = Dancer::Request->new_for_request($method => $path);
    ok(Dancer::App->find_route_through_apps($req), $test_name);
}

sub route_doesnt_exist {
    my ($req, $test_name) = @_;

    my ($method, $path) = @$req;
    $test_name ||= "no route exists for $method $path";

    $req = Dancer::Request->new_for_request($method => $path);
    ok(!defined(Dancer::App->find_route_through_apps($req)), $test_name);
}

# Response status

sub response_exists {
    my ($req, $test_name) = @_;
    $test_name ||= "a response is found for @$req";

    my $response = dancer_response(@$req);
    ok(defined($response), $test_name);
}

sub response_doesnt_exist {
    my ($req, $test_name) = @_;
    $test_name ||= "no response found for @$req";

    my $response = dancer_response(@$req);
    ok(!defined($response), $test_name);
}

sub response_status_is {
    my ($req, $status, $test_name) = @_;
    $test_name ||= "response status is $status for @$req";

    my $response = dancer_response(@$req);
    is $response->status, $status, $test_name;
}

sub response_status_isnt {
    my ($req, $status, $test_name) = @_;
    $test_name ||= "response status is not $status for @$req";

    my $response = dancer_response(@$req);
    isnt $response->{status}, $status, $test_name;
}

# Response content

sub response_content_is {
    my ($req, $matcher, $test_name) = @_;
    $test_name ||= "response content looks good for @$req";

    my $response = dancer_response(@$req);
    is $response->{content}, $matcher, $test_name;
}

sub response_content_isnt {
    my ($req, $matcher, $test_name) = @_;
    $test_name ||= "response content looks good for @$req";

    my $response = dancer_response(@$req);
    isnt $response->{content}, $matcher, $test_name;
}

sub response_content_like {
    my ($req, $matcher, $test_name) = @_;
    $test_name ||= "response content looks good for @$req";

    my $response = dancer_response(@$req);
    like $response->{content}, $matcher, $test_name;
}

sub response_content_unlike {
    my ($req, $matcher, $test_name) = @_;
    $test_name ||= "response content looks good for @$req";

    my $response = dancer_response(@$req);
    unlike $response->{content}, $matcher, $test_name;
}

sub response_content_is_deeply {
    my ($req, $matcher, $test_name) = @_;
    $test_name ||= "response content looks good for @$req";

    my $response = dancer_response(@$req);
    is_deeply $response->{content}, $matcher, $test_name;
}

sub response_is_file {
    my ($req, $test_name) = @_;
    $test_name ||= "a file is returned for @$req";

    my $response = _get_file_response($req);
    ok(defined($response), $test_name);
}

sub response_headers_are_deeply {
    my ($req, $expected, $test_name) = @_;
    $test_name ||= "headers are as expected for @$req";

    my $response = dancer_response(@$req);
    is_deeply($response->headers_to_array, $expected, $test_name);
}

sub dancer_response {
    my ($method, $path, $args) = @_;
    $args ||= {};

    if ($method =~ /^(?:PUT|POST)$/ && $args->{body}) {
        my $body = $args->{body};

        # coerce hashref into an url-encoded string
        if (ref($body) && (ref($body) eq 'HASH')) {
            my @tokens;
            while (my ($name, $value) = each %{$body}) {
                $name  = _url_encode($name);
                $value = _url_encode($value);
                push @tokens, "${name}=${value}";
            }
            $body = join('&', @tokens);
        }

        my $l = length $body;
        open my $in, '<', \$body;
        $ENV{'CONTENT_LENGTH'} = $l;
        $ENV{'CONTENT_TYPE'}   = 'application/x-www-form-urlencoded';
        $ENV{'psgi.input'}     = $in;
    }

    my ($params, $body, $headers) = @$args{qw(params body headers)};

    if ($headers and (my @headers = @$headers)) {
        while (my $h = shift @headers) {
            if ($h =~ /content-type/i) {
                $ENV{'CONTENT_TYPE'} = shift @headers;
            }
        }
    }

    my $request = Dancer::Request->new_for_request(
        $method => $path,
        $params, $body, HTTP::Headers->new(@$headers)
    );

    Dancer::SharedData->request($request);

    my $get_action = Dancer::Renderer::get_action_response();
    my $response = Dancer::SharedData->response();
    $response->content('') if $method eq 'HEAD';
    Dancer::SharedData->reset_response();
    return $response if $get_action;
    (defined $response && $response->exists) ? return $response : return undef;
}

sub get_response {
    Dancer::Deprecation->deprecated(
        fatal   => 1,
        feature => 'get_response',
        reason  => 'Use dancer_response() instead.',
    );
}

# private

sub _url_encode {
    my $string = shift;
    $string =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
    return $string;
}

sub _get_file_response {
    my ($req) = @_;
    my ($method, $path, $params) = @$req;
    my $request = Dancer::Request->new_for_request($method => $path, $params);
    Dancer::SharedData->request($request);
    return Dancer::Renderer::get_file_response();
}

sub _get_handler_response {
    my ($req) = @_;
    my ($method, $path, $params) = @$req;
    my $request = Dancer::Request->new_for_request($method => $path, $params);
    return Dancer::Handler->handle_request($request);
}

1;
__END__

=pod

=head1 NAME

Dancer::Test - Test helpers to test a Dancer application

=head1 SYNOPSYS

    use strict;
    use warnings;
    use Test::More tests => 2;

    use MyWebApp;
    use Dancer::Test;

    response_status_is [GET => '/'], 200, "GET / is found";
    response_content_like [GET => '/'], qr/hello, world/, "content looks good for /";


=head1 DESCRIPTION

This module provides test helpers for testing Dancer apps.

Be careful, the module loading order in the example above is very important.
Make sure to use C<Dancer::Test> B<after> importing the application package
otherwise your appdir will be automatically set to C<lib> and your test script
won't be able to find views, conffiles and other application content.

=head1 METHODS

=head2 route_exists([$method, $path], $test_name)

Asserts that the given request matches a route handler in Dancer's
registry.

    route_exists [GET => '/'], "GET / is handled";

=head2 route_doesnt_exist([$method, $path], $test_name)

Asserts that the given request does not match any route handler 
in Dancer's registry.

    route_doesnt_exist [GET => '/bogus_path'], "GET /bogus_path is not handled";


=head2 response_exists([$method, $path], $test_name)

Asserts that a response is found for the given request (note that even though 
a route for that path might not exist, a response can be found during request
processing, because of filters).

    response_exists [GET => '/path_that_gets_redirected_to_home'],
        "response found for unknown path";

=head2 response_doesnt_exist([$method, $path], $test_name)

Asserts that no response is found when processing the given request.

    response_doesnt_exist [GET => '/unknown_path'],
        "response not found for unknown path";

=head2 response_status_is([$method, $path], $status, $test_name)

Asserts that Dancer's response for the given request has a status equal to the
one given.

    response_status_is [GET => '/'], 200, "response for GET / is 200";

=head2 response_status_isnt([$method, $path], $status, $test_name)

Asserts that the status of Dancer's response is not equal to the
one given.

    response_status_isnt [GET => '/'], 404, "response for GET / is not a 404";

=head2 response_content_is([$method, $path], $expected, $test_name)

Asserts that the response content is equal to the C<$expected> string.

    response_content_is [GET => '/'], "Hello, World", 
        "got expected response content for GET /";

=head2 response_content_isnt([$method, $path], $not_expected, $test_name)

Asserts that the response content is not equal to the C<$not_expected> string.

    response_content_isnt [GET => '/'], "Hello, World", 
        "got expected response content for GET /";

=head2 response_content_is_deeply([$method, $path], $expected_struct, $test_name)

Similar to response_content_is(), except that if response content and 
$expected_struct are references, it does a deep comparison walking each data 
structure to see if they are equivalent.  

If the two structures are different, it will display the place where they start
differing.

    response_content_is_deeply [GET => '/complex_struct'], 
        { foo => 42, bar => 24}, 
        "got expected response structure for GET /complex_struct";

=head2 response_content_like([$method, $path], $regexp, $test_name)

Asserts that the response content for the given request matches the regexp
given.

    response_content_like [GET => '/'], qr/Hello, World/, 
        "response content looks good for GET /";

=head2 response_content_unlike([$method, $path], $regexp, $test_name)

Asserts that the response content for the given request does not match the regexp
given.

    response_content_unlike [GET => '/'], qr/Page not found/, 
        "response content looks good for GET /";

=head2 response_headers_are_deeply([$method, $path], $expected, $test_name)

Asserts that the response headers data structure equals the one given.

    response_headers_are_deeply [GET => '/'], [ 'X-Powered-By' => 'Dancer 1.150' ];

=head2 dancer_response($method, $path, { params => $params, body => $body, headers => $headers })

Returns a Dancer::Response object for the given request.
Only $method and $path are required.
$params is a hashref, $body is a string and $headers can be an arrayref or
a HTTP::Headers object.
A good reason to use this function is for
testing POST requests. Since POST requests may not be idempotent, it is
necessary to capture the content and status in one shot. Calling the
response_status_is and response_content_is functions in succession would make
two requests, each of which could alter the state of the application and cause
Schrodinger's cat to die.

    my $response = dancer_response POST => '/widgets';
    is $response->{status}, 202, "response for POST /widgets is 202";
    is $response->{content}, "Widget #1 has been scheduled for creation",
        "response content looks good for first POST /widgets";

    $response = dancer_response POST => '/widgets';
    is $response->{status}, 202, "response for POST /widgets is 202";
    is $response->{content}, "Widget #2 has been scheduled for creation",
        "response content looks good for second POST /widgets";

=head2 get_response([$method, $path])

This method is B<DEPRECATED>.  Use dancer_response() instead.

=head1 LICENSE

This module is free software and is distributed under the same terms as Perl
itself.

=head1 AUTHOR

This module has been written by Alexis Sukrieh <sukria@sukria.net>

=head1 SEE ALSO

L<Test::More>

=cut
