use strict;
use warnings;

### after: use lib qw(@RT_LIB_PATH@);
use lib qw(/opt/rt3/local/lib /opt/rt3/lib);

package RT::Authen::ExternalAuth::Test;

our @ISA;
BEGIN {
    local $@;
    eval { require RT::Test; 1 } or do {
        require Test::More;
        Test::More::BAIL_OUT(
            "requires 3.8 to run tests. Error:\n$@\n"
            ."You may need to set PERL5LIB=/path/to/rt/lib"
        );
    };
    push @ISA, 'RT::Test';
}

sub import {
    my $class = shift;
    my %args  = @_;

    $args{'requires'} ||= [];
    if ( $args{'testing'} ) {
        unshift @{ $args{'requires'} }, 'RT::Authen::ExternalAuth';
    } else {
        $args{'testing'} = 'RT::Authen::ExternalAuth';
    }

    if ( delete $args{'ldap'} ) {
        local $@;
        eval {
            require Net::LDAP;
            require Net::LDAP::Server::Test;
            1;
        } or do {
            require Test::More;
            Test::More::plan( skip_all => 'Unable to test without LDAP modules: '. $@ );
            exit;
        }
    }

    $class->SUPER::import( %args );
    $class->export_to_level(1);

    require RT::Authen::ExternalAuth;
}

my %ldap;
sub bootstrap_ldap_server {
    my $self = shift;

    my $port = RT::Test->generate_port;

    require Net::LDAP::Server::Test;
    my $server = Net::LDAP::Server::Test->new( $port, auto_schema => 1 );
    return () unless $server;

    my $client = Net::LDAP->new( "localhost:$port" );
    $client->bind;

    @ldap{'server','client'} = ($server, $client);
    return ($server, $client, "localhost:$port", $port);
}

sub bootstrap_ldap_basics {
    my $self = shift;
    my ($server, $client, $address, $port) = $self->bootstrap_ldap_server;

    RT->Config->Set( Plugins                     => 'RT::Authen::ExternalAuth' );
    RT->Config->Set( ExternalAuthPriority        => ['My_LDAP'] );
    RT->Config->Set( ExternalInfoPriority        => ['My_LDAP'] );
    RT->Config->Set( ExternalServiceUsesSSLorTLS => 0 );
    RT->Config->Set( AutoCreateNonExternalUsers  => 0 );
    RT->Config->Set( AutoCreate  => undef );
    RT->Config->Set(
        ExternalSettings => {
            'My_LDAP' => {
                'type'            => 'ldap',
                'server'          => $address,
                'base'            => 'dc=bestpractical,dc=com',
                'filter'          => '(objectClass=*)',
                'd_filter'        => '()',
                'tls'             => 0,
                'net_ldap_args'   => [ version => 3 ],
                'attr_match_list' => [ 'Name', 'EmailAddress' ],
                'attr_map'        => {
                    'Name'         => 'uid',
                    'EmailAddress' => 'mail',
                },
            },
        },
    );
    return ($server, $client);
}

sub add_ldap_user {
    my $self = shift;
    my %args = @_;

    $args{'uid'} ||= $args{'cn'};
    $args{'cn'} ||= $args{'uid'};

    my $dn = delete $args{'dn'};
    $dn ||= "uid=". $args{'uid'} .",dc=bestpractical,dc=com";

    $args{'objectClass'} ||= 'User';
    $args{'userPassword'} ||= 'password';

    return $ldap{'client'}->add( $dn, attr => [%args] );
}

{ my $i = 0;
sub add_ldap_user_simple {
    my $self = shift;
    my %args = @_;

    my $name = "testuser". ++$i;

    s/\%name\b/$name/g foreach grep defined, values %args;

    $self->add_ldap_user(
        cn    => $name,
        mail  => "$name\@invalid.tld",
        %args,
    );
    return $name;
} }

1;
