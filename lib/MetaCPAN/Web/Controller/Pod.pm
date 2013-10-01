package MetaCPAN::Web::Controller::Pod;

use Moose;
use namespace::autoclean;
use Try::Tiny;
use HTML::Restrict;

BEGIN { extends 'MetaCPAN::Web::Controller' }

with qw(
    MetaCPAN::Web::Role::ReleaseInfo
);

sub root : Chained('/') PathPart('pod') CaptureArgs(0) {
}

# /pod/$name
sub find : Chained('root') PathPart('') Args(1) {
    my ( $self, $c, @path ) = @_;

    # TODO: Pass size param so we can disambiguate?
    $c->stash->{pod_file} = $c->model('API::Module')->find(@path)->recv;

    # TODO: Disambiguate if there's more than once match. #176

    $c->forward('view', [@path]);
}

# /pod/release/$AUTHOR/$release/@path
sub release : Chained('root') Local Args {
    my ( $self, $c, @path ) = @_;

    # force consistent casing in URLs
    if ( @path > 2 && $path[0] ne uc($path[0]) ) {
        $c->res->redirect( '/pod/release/' . join( '/', uc(shift @path), @path ), 301 );
        $c->detach();
    }

    $c->stash->{pod_file} = $c->model('API::Module')->get(@path)->recv;
    $c->forward('view', [@path]);
}

sub view : Private {
    my ( $self, $c, @path ) = @_;

    my $data = $c->stash->{pod_file};

    if($data->{directory}) {
        $c->res->redirect( '/source/' . join( '/', @path ), 301 );
        $c->detach;
    }

    my ( $documentation, $pod )
        = map { $_->{name}, $_->{associated_pod} }
        grep { @path > 1 || $path[0] eq $_->{name} }
        grep { !$data->{documentation} || $data->{documentation} eq $_->{name} }
        grep { $_->{associated_pod} } @{ $data->{module} || [] };
    $data->{documentation} = $documentation if $documentation;

    $c->detach('/not_found') unless ( $data->{name} );
    my $reqs = $self->api_requests(
        $c,
        {   pod => $c->model('API')
                ->request( '/pod/' . ( $pod || join( '/', @path ) ) . '?show_errors=1' ),
            release => $c->model('API::Release')
                ->get( @{$data}{qw(author release)} ),
        },
        $data,
    );
    $reqs = $self->recv_all($reqs);
    $self->stash_api_results( $c, $reqs, $data );
    $self->add_favorites_data( $data, $reqs->{favorites}, $data );

    my $hr = HTML::Restrict->new;
    $hr->set_rules(
        {   a       => [qw( href target )],
            b       => [],
            br      => [],
            caption => [],
            center  => [],
            code    => [],
            dd      => ['id'],
            div     => [qw(id style)],
            dl      => ['id'],
            dt      => ['id'],
            em      => [],
            h1      => ['id'],
            h2      => ['id'],
            h3      => ['id'],
            h4      => ['id'],
            h5      => ['id'],
            h6      => ['id'],
            i       => [],
            img     => [qw( alt border height width src style title / )],
            li      => ['id'],
            ol      => [],
            p       => [qw(class style)],
            pre     => [qw(id class style)],
            span    => [qw(style)],
            strong  => [],
            sub     => [],
            sup     => [],
            table => [qw( style class border cellspacing cellpadding align )],
            tbody => [],
            td    => [qw(style class)],
            tr    => [qw(style class)],
            u     => [],
            ul    => ['id'],
        }
    );

    # ensure page is not cached when latest release is a trial
    $c->res->last_modified(
               $reqs->{versions}->{hits}->{hits}->[0]->{fields}->{date}
            || $data->{date} );

    $c->stash(
        {   module   => $data,
            pod      => $hr->process( $reqs->{pod}->{raw} ),
            release  => $reqs->{release}->{hits}->{hits}->[0]->{_source},
            template => 'pod.html',
        }
    );
    unless ($c->stash->{pod}) {
        $c->stash(
            pod_error => $reqs->{pod}->{message},
        );
    }
}

1;
