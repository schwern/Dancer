package Dancer::Serializer;

# Factory for serializer engines

use strict;
use warnings;
use Dancer::ModuleLoader;
use Dancer::Engine;
use Dancer::Error;
use Dancer::SharedData;

my $_engine;
sub engine {$_engine}

# TODO : change the serializer according to $name
sub init {
    my ( $class, $name, $config ) = @_;
    $name ||= 'Json';
    $_engine = Dancer::Engine->build( 'serializer' => $name, $config );
}

# takes a response object, and look wether or not it should be
# serialized.
# returns an error object if the serializer fails
sub sanitize_response {
    my ($class, $response) = @_;
    my $content = $response->{content};

    if (ref($content) && (ref($content) ne 'GLOB')) {
        local $@;
        eval { $content = engine->serialize($content) };

        # the serializer failed, replace the response with an error object
        if ($@) {
            my $error = Dancer::Error->new(
                code => 500,
                message => "Serializer (".ref($_engine).") ".
                    "failed at serializing ".$response->{content}.":\n$@",
            );
            $response = $error->render;
        }

        # the serializer succeeded, alter the response object accordingly
        else {
            $response->update_headers('Content-Type' => engine->content_type);
            $response->{content} = $content;
        }
    }

    return $response;
}

sub handle_request {

    my $request = Dancer::SharedData->request;

    return
        unless Dancer::Serializer->engine->content_type eq
            $request->content_type;

    return
        unless ( $request->method eq 'PUT'
        || $request->method eq 'POST' );

    my $rdata      = $request->body;
    my $new_params = Dancer::Serializer->engine->deserialize($rdata);
    if ( keys %{ $request->{params} } ) {
        $request->{params} = { %{ $request->{params} }, %$new_params };
    }
    else {
        $request->{params} = $new_params;
    }
    Dancer::SharedData->request($request);
}


1;

__END__

=pod

=head1 NAME

Dancer::Serializer - serializer support in Dancer

=head1 DESCRIPTION

This module is the wrapper that provides support for different
serializers.

=head1 USAGE

=head2 Default engine

The default serializer used by Dancer::Serializer is
L<Dancer::Serializer::Mutable>.
You can choose another serializer by setting the B<serializer> configuration
variable.

=head2 Configuration

The B<serializer> configuration variable tells Dancer which serializer to use
to deserialize request and serialize response.

You change it either in your config.yml file:

    serializer: "YAML"

Or in the application code:

    # setting JSON as the default serializer
    set serializer => 'JSON';

=head1 AUTHORS

This module has been written by Alexis Sukrieh. See the AUTHORS file that comes
with this distribution for details.

=head1 LICENSE

This module is free software and is released under the same terms as Perl
itself.

=head1 SEE ALSO

See L<Dancer> for details about the complete framework.

You can also search the CPAN for existing engines in the Dancer::Template
namespace.

=cut
